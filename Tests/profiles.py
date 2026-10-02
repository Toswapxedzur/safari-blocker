#!/usr/bin/env python3
"""Exercise provisioning metadata rejection without using account credentials."""
import copy
import datetime
import importlib.util
import pathlib

path = pathlib.Path(__file__).resolve().parents[1] / 'scripts/embed-profiles.py'
spec = importlib.util.spec_from_file_location('embed_profiles', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
TEAM = 'EXAMPLETEAM'
BUNDLE = 'com.adamancia.vault.safari.development'
GROUP = 'group.com.adamancia.vault.development'
fixture = {'TeamIdentifier': [TEAM], 'ApplicationIdentifierPrefix': [TEAM],
           'DeveloperCertificates': [b'fixture authorized certificate'],
           'ExpirationDate': datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
           'Entitlements': {'com.apple.application-identifier': TEAM + '.' + BUNDLE,
                            'com.apple.developer.team-identifier': TEAM,
                            'com.apple.security.application-groups': [GROUP]}}
assert module.validate_profile(fixture, BUNDLE, GROUP) == (TEAM, TEAM + '.' + BUNDLE)
checks = 1

def refuses(label, mutate, previous_team=None):
    global checks
    value = copy.deepcopy(fixture)
    mutate(value)
    try:
        module.validate_profile(value, BUNDLE, GROUP, previous_team)
    except ValueError:
        checks += 1
        return
    raise AssertionError(label)

refuses('wrong environment group', lambda p: p['Entitlements'].update({'com.apple.security.application-groups': ['group.com.adamancia.vault']}))
refuses('wrong bundle identity', lambda p: p['Entitlements'].update({'com.apple.application-identifier': TEAM + '.com.unrelated.app'}))
refuses('expired profile', lambda p: p.update({'ExpirationDate': datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)}))
refuses('different teams', lambda p: None, previous_team='OTHERTEAM')
refuses('inconsistent entitlement team', lambda p: p['Entitlements'].update({'com.apple.developer.team-identifier': 'OTHERTEAM'}))
refuses('missing group authorization', lambda p: p['Entitlements'].pop('com.apple.security.application-groups'))
refuses('missing application authorization', lambda p: p['Entitlements'].pop('com.apple.application-identifier'))
refuses('missing signing certificate', lambda p: p.pop('DeveloperCertificates'))
legacy = copy.deepcopy(fixture)
legacy['ApplicationIdentifierPrefix'] = ['LEGACYPREFIX']
legacy['Entitlements']['com.apple.application-identifier'] = 'LEGACYPREFIX.' + BUNDLE
assert module.validate_profile(legacy, BUNDLE, GROUP) == (TEAM, 'LEGACYPREFIX.' + BUNDLE)
checks += 1
print('SAFARI_PROFILE_RESULT: OK (%d metadata checks; signing execution remains separate)' % checks)

# Exercise the packaging script itself using account-free command fixtures.
# These are not Apple signatures; the runtime gate remains a separate check.
import os
import plistlib
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix='safari-profile-fixture-') as temporary:
    base = pathlib.Path(temporary)
    app = base / 'Safari Vault Development.app'
    extension = app / 'Contents/PlugIns/SafariVaultExtension.appex'
    for bundle, identifier in [(app, BUNDLE), (extension, BUNDLE + '.extension')]:
        (bundle / 'Contents').mkdir(parents=True, exist_ok=True)
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier}))
    (base / 'SafariVault.entitlements').write_bytes(plistlib.dumps({
        'com.apple.security.app-sandbox': True, 'com.apple.security.application-groups': [GROUP]}))
    fixtures = base / 'profiles'
    fixtures.mkdir()
    for name, identifier in [('app', BUNDLE), ('extension', BUNDLE + '.extension')]:
        data = copy.deepcopy(fixture)
        data['ExpirationDate'] = data['ExpirationDate'].replace(tzinfo=None)
        data['Entitlements']['com.apple.application-identifier'] = TEAM + '.' + identifier
        (fixtures / (name + '.plist')).write_bytes(plistlib.dumps(data))
        (fixtures / (name + '.provisionprofile')).write_bytes(('fixture CMS ' + name).encode())
    tools = base / 'tools'
    tools.mkdir()
    security = tools / 'security'
    security.write_text('''#!/usr/bin/env python3
import pathlib,sys
path=pathlib.Path(sys.argv[-1])
sys.stdout.buffer.write(path.with_suffix('.plist').read_bytes())
''')
    codesign = tools / 'codesign'
    codesign.write_text('''#!/usr/bin/env python3
import os,pathlib,plistlib,sys
args=sys.argv[1:]
if '-dv' in args: print('TeamIdentifier='+os.environ.get('SAFARI_FIXTURE_TEAM','EXAMPLETEAM'),file=sys.stderr)
elif any(arg.startswith('--extract-certificates') for arg in args):
    assert len(args)==3 and args[0]=='-d' and args[1].startswith('--extract-certificates='), 'codesign requires its optional certificate prefix joined with ='
    pathlib.Path(args[1].split('=',1)[1]+'0').write_bytes(os.environ.get('SAFARI_FIXTURE_CERT','fixture authorized certificate').encode())
else:
    data=plistlib.loads((pathlib.Path(os.environ['SAFARI_FIXTURE_OUTPUT'])/(pathlib.Path(args[-1]).name+'.entitlements')).read_bytes())
    if os.environ.get('SAFARI_FIXTURE_UNSANDBOXED'): data['com.apple.security.app-sandbox']=False
    sys.stdout.buffer.write(plistlib.dumps(data))
''')
    security.chmod(0o755)
    codesign.chmod(0o755)
    env = {**os.environ, 'PATH': str(tools) + ':' + os.environ['PATH'], 'SAFARI_FIXTURE_OUTPUT': str(base)}
    args = [str(app), str(extension), GROUP, str(fixtures / 'app.provisionprofile'), str(fixtures / 'extension.provisionprofile')]
    subprocess.run([sys.executable, str(path), *args], env=env, check=True, capture_output=True)
    assert (app / 'Contents/embedded.provisionprofile').read_bytes() == (fixtures / 'app.provisionprofile').read_bytes()
    assert (extension / 'Contents/embedded.provisionprofile').read_bytes() == (fixtures / 'extension.provisionprofile').read_bytes()
    subprocess.run([sys.executable, str(path), '--verify', *args], env=env, check=True, capture_output=True)
    for patch in [{'SAFARI_FIXTURE_TEAM': 'OTHERTEAM'}, {'SAFARI_FIXTURE_CERT': 'other certificate from same team'}, {'SAFARI_FIXTURE_UNSANDBOXED': '1'}]:
        result = subprocess.run([sys.executable, str(path), '--verify', *args], env={**env, **patch}, capture_output=True)
        assert result.returncode != 0, 'invalid final signature was accepted'
    print('SAFARI_PROFILE_PACKAGING_RESULT: OK (5 packaging/signature command fixtures; no Apple signing execution)')
