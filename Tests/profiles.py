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
legacy = copy.deepcopy(fixture)
legacy['ApplicationIdentifierPrefix'] = ['LEGACYPREFIX']
legacy['Entitlements']['com.apple.application-identifier'] = 'LEGACYPREFIX.' + BUNDLE
assert module.validate_profile(legacy, BUNDLE, GROUP) == (TEAM, 'LEGACYPREFIX.' + BUNDLE)
checks += 1
print('SAFARI_PROFILE_RESULT: OK (%d metadata checks; signing execution remains separate)' % checks)
