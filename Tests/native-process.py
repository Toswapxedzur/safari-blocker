#!/usr/bin/env python3
"""Exercise the actual native message handler in disposable mini1 processes."""
import json, os, pathlib, subprocess, sys, tempfile, time
binary=pathlib.Path(sys.argv[1])
def check(value,label):
    if not value: raise AssertionError(label)
    print('PASS '+label)
with tempfile.TemporaryDirectory(prefix='safari-native-process-') as directory:
    env=dict(os.environ,SAFARI_TEST_DIRECTORY=directory)
    def request(payload,profile='profile-one',timeout=5):
        start=time.monotonic()
        result=subprocess.run([str(binary),'--native-message'],input=json.dumps(payload),text=True,capture_output=True,
                              env=dict(env,SAFARI_TEST_PROFILE=profile),timeout=timeout)
        try: answer=json.loads(result.stdout.strip().splitlines()[-1])
        except Exception: raise AssertionError('native request missing reply: '+result.stdout+' '+result.stderr)
        return answer,result.returncode,time.monotonic()-start
    # Actual native endpoint stages across requests in one handler process.
    staged_group='staged'
    counter="(on,v)=>{v.state.run=(v.state.run||0)+1;}"
    def staged_message(kind, **fields):
        return {'type':'event-sandbox-request','payload':dict(kind=kind,groupId=staged_group,groupIds=[staged_group],**fields)}
    staged_messages=[staged_message('prepare-source',source=counter,state={}),
                     staged_message('commit-source',token='$previousToken'),
                     staged_message('prepare-source',source=counter,state={'run':1}),
                     staged_message('commit-source',token='$previousToken')]
    staged_run=subprocess.run([str(binary),'--native-messages'],input=json.dumps(staged_messages),text=True,capture_output=True,
                              env=dict(env,SAFARI_TEST_PROFILE='staged-profile'),timeout=5)
    staged_replies=[json.loads(line) for line in staged_run.stdout.splitlines()]
    check(staged_run.returncode==0 and staged_replies[-1]['result']['states']['staged']['run']==2,
          'actual native staged transport retains initialization memory across Runs')
    answer,code,_=request(staged_message('prepare-source',source="(on,v)=>{v.state.uncommitted=true;}",state={}),profile='uncommitted-profile')
    check(answer['result']['ok'] and code==0,'native process can exit with a prepared uncommitted candidate')
    answer,code,_=request(staged_message('dispatch-event',descriptor={'type':'tick'}),profile='uncommitted-profile')
    check(answer['result']['states']=={} and code==0,'cold handler never replays an uncommitted source')
    active_groups=['a-healthy','z-hang','registration-hang']
    def rule(payload,group_ids=None,**kw):
        return request({'type':'event-sandbox-request','payload':dict(payload,groupIds=active_groups if group_ids is None else group_ids)},**kw)
    tick={'kind':'dispatch-event','descriptor':{'type':'tick','now':1000,'data':{'tabId':4}}}
    source="(on,v)=>on('tick',()=>{v.state.n=(v.state.n||0)+1;v.log(v.state.n)})"
    answer,code,_=rule({'kind':'load-source','groupId':'a-healthy','source':source,'state':{'n':10}})
    check(answer['result']['ok'] and code==0,'native load replies')
    answer,code,_=rule(tick)
    check(answer['result']['states']['a-healthy']['n']==11 and code==0,'native process restores source/state')
    bad="(on,v)=>on('tick',()=>{while(true){}})"
    answer,code,_=rule({'kind':'load-source','groupId':'z-hang','source':bad,'state':{}})
    check(answer['result']['ok'] and code==0,'native hang rule registration bounded')
    answer,code,duration=rule(tick)
    check(answer['result']['quarantine']['groupId']=='z-hang' and code==124 and duration<3,'infinite rule terminates only native handler by deadline')
    answer,code,_=rule(tick)
    check(answer['result']['states']['a-healthy']['n']==12 and code==0,'healthy sibling restores last committed state after killed handler')
    answer,code,duration=rule({'kind':'load-source','groupId':'z-hang','source':bad,'state':{}})
    check(answer['result']['ok']==False and code==0 and duration<1.2,'cold startup cannot re-execute quarantined source')
    answer,code,_=rule(tick,profile='profile-two')
    check(not answer['result']['logs'] and code==0,'other Safari profile sees no source or memory')
    answer,code,_=rule({'kind':'load-source','groupId':'z-hang','source':"(on,v)=>on('tick',()=>v.log('fixed'))",'state':{}})
    check(answer['result']['ok'] and code==0,'edited rule clears native quarantine')
    answer,code,_=rule(tick)
    check(not answer['result'].get('quarantine') and any(log['groupId']=='z-hang' for log in answer['result']['logs']),'repaired rule runs beside healthy sibling')
    registration="(on,v)=>{while(true){}}"
    answer,code,duration=rule({'kind':'load-source','groupId':'registration-hang','source':registration,'state':{}})
    check(answer['result']['quarantine']['groupId']=='registration-hang' and code==124 and duration<3,'registration infinite loop is hard quarantined')
    answer,code,duration=rule({'kind':'load-source','groupId':'registration-hang','source':registration,'state':{}})
    check(answer['result']['ok']==False and code==0 and duration<1.2,'failed registration hash prevents cold restart loop')
    answer,code,_=rule(tick,group_ids=['a-healthy'])
    check(answer['result']['ok'] and set(answer['result']['states'])=={'a-healthy'} and not answer['result'].get('quarantine'),
          'cold deletion prunes stale sources and quarantine before restore')
    answer,code,_=rule(tick,group_ids=[])
    check(answer['result']['ok'] and not answer['result']['states'] and not answer['result']['logs'],
          'reset-to-empty storage cannot resurrect native groups')
    answer,code,_=rule(tick)
    check(answer['result']['ok'] and not answer['result']['states'],
          'pruned source cannot reappear in a later cold process')
    answer,code,_=request({'type':'event-sandbox-request','payload':tick})
    check(answer['ok']==False and code==0,'missing authoritative roster fails closed')
    # Simulate a stale journal whose registration code would hang if restored.
    import hashlib
    journal=pathlib.Path(directory)/('rules-'+hashlib.sha256(b'profile-deleted').hexdigest()+'.json')
    journal.write_text(json.dumps({'version':1,'groups':{'deleted':{'source':registration,'state':{},'suppressed':False}},'quarantine':{},'quarantinedSources':{}}))
    answer,code,duration=rule(tick,group_ids=[],profile='profile-deleted')
    check(answer['result']['ok'] and code==0 and duration<1.2,
          'deleted infinite source is pruned before registration can execute')
    deleted_load={'kind':'load-source','groupId':'deleted','source':registration,'state':{}}
    answer,code,duration=rule(deleted_load,group_ids=[],profile='profile-racing-delete')
    check(not answer['ok'] and code==0 and duration<1.2,
          'cold stale load refuses absent group before source evaluation')
    messages=[
        {'type':'event-sandbox-request','payload':dict(kind='load-source',groupId='deleted',source=source,state={},groupIds=['deleted'])},
        {'type':'event-sandbox-request','payload':dict(deleted_load,groupIds=[])},
        {'type':'event-sandbox-request','payload':dict(tick,groupIds=[])},
    ]
    result=subprocess.run([str(binary),'--native-messages'],input=json.dumps(messages),text=True,capture_output=True,
                          env=dict(env,SAFARI_TEST_PROFILE='profile-warm-delete'),timeout=5)
    replies=[json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
    check(result.returncode==0 and len(replies)==3 and replies[0]['result']['ok'] and not replies[1]['ok']
          and not replies[2]['result']['states'] and not replies[2]['result']['logs'],
          'warm stale load cannot reinsert a deleted source or produce actions')
    answer,code,_=rule(tick,group_ids=['deleted'],profile='profile-warm-delete')
    check(answer['result']['ok'] and not answer['result']['states'] and code==0,
          'refused warm source remains absent after a cold restart')
    answer,code,_=request({'kind':'local-hub-challenge' ,'v':4,'program':'chrome','challenge':'a'*43})
    check(answer['ok']==False and code==0,'Safari native endpoint refuses Chromium impersonation')
print('SAFARI_PROCESS_RESULT: OK')
