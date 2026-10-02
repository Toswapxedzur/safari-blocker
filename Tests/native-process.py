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
    def rule(payload,**kw): return request({'type':'event-sandbox-request','payload':payload},**kw)
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
    answer,code,_=request({'kind':'local-hub-challenge' ,'v':4,'program':'chrome','challenge':'a'*43})
    check(answer['ok']==False and code==0,'Safari native endpoint refuses Chromium impersonation')
print('SAFARI_PROCESS_RESULT: OK')
