#!/usr/bin/env python3
"""Validate and embed Apple profiles without printing their private contents."""
import datetime
import pathlib
import plistlib
import subprocess
import sys
import tempfile


def validate_profile(data, bundle_id, group, previous_team=None):
    entitlements = data.get('Entitlements', {})
    teams = data.get('TeamIdentifier', [])
    if len(teams) != 1 or not isinstance(teams[0], str) or not teams[0] or (previous_team is not None and previous_team != teams[0]):
        raise ValueError('Containing app and extension must use the same Apple developer team.')
    team = teams[0]
    if entitlements.get('com.apple.developer.team-identifier') != team:
        raise ValueError('The provisioning profile has inconsistent developer team authorization.')
    identifier = entitlements.get('com.apple.application-identifier', entitlements.get('application-identifier', ''))
    prefixes = data.get('ApplicationIdentifierPrefix', [team])
    candidates = [prefix + '.' + bundle_id for prefix in prefixes if isinstance(prefix, str) and prefix]
    expected = next((candidate for candidate in candidates if identifier == candidate or
                     isinstance(identifier, str) and identifier.endswith('*') and candidate.startswith(identifier[:-1])), None)
    if expected is None:
        raise ValueError('The provisioning profile does not authorize this Safari bundle identifier.')
    if group not in entitlements.get('com.apple.security.application-groups', []):
        raise ValueError('The provisioning profile does not authorize the shared Vault App Group.')
    certificates = data.get('DeveloperCertificates', [])
    if not certificates or not all(isinstance(certificate, bytes) for certificate in certificates):
        raise ValueError('The provisioning profile does not authorize a signing certificate.')
    expiration = data.get('ExpirationDate')
    if isinstance(expiration, datetime.datetime) and expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=datetime.timezone.utc)
    if not isinstance(expiration, datetime.datetime) or expiration <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('The provisioning profile has expired.')
    return team, expected


def main():
    arguments = sys.argv[1:]
    verify = bool(arguments and arguments[0] == '--verify')
    if verify:
        arguments.pop(0)
    if len(arguments) != 5:
        raise SystemExit('Expected app, extension, App Group, app profile and extension profile.')
    app, extension = map(pathlib.Path, arguments[:2])
    group = arguments[2]
    app_profile, extension_profile = map(pathlib.Path, arguments[3:])
    team = None
    prepared = []
    for bundle, profile in [(app, app_profile), (extension, extension_profile)]:
        if not profile.is_file():
            raise SystemExit('A selected Apple provisioning profile is missing.')
        decoded = subprocess.run(['security', 'cms', '-D', '-i', str(profile)], check=True, capture_output=True).stdout
        data = plistlib.loads(decoded)
        info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
        team, expected = validate_profile(data, info['CFBundleIdentifier'], group, team)
        signing_entitlements = plistlib.loads((app.parent / 'SafariVault.entitlements').read_bytes())
        signing_entitlements['com.apple.application-identifier'] = expected
        signing_entitlements['com.apple.developer.team-identifier'] = team
        if verify:
            signature = subprocess.run(['codesign', '-dv', '--verbose=4', str(bundle)], capture_output=True, text=True, check=True)
            signed_team = next((line.partition('=')[2] for line in signature.stderr.splitlines() if line.startswith('TeamIdentifier=')), '')
            if signed_team != team:
                raise ValueError('Safari signing identity and profile belong to different Apple developer teams.')
            with tempfile.TemporaryDirectory(prefix='safari-signing-certificate-') as temporary:
                prefix = pathlib.Path(temporary) / 'certificate'
                subprocess.run(['codesign', '-d', '--extract-certificates', str(prefix), str(bundle)], capture_output=True, check=True)
                if prefix.with_name(prefix.name + '0').read_bytes() not in data['DeveloperCertificates']:
                    raise ValueError('The Safari provisioning profile does not authorize the actual signing certificate.')
            actual = plistlib.loads(subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], capture_output=True, check=True).stdout)
            if any(actual.get(key) != value for key, value in signing_entitlements.items()):
                raise ValueError('Safari bundle does not carry its expected authorized entitlements.')
            if (bundle / 'Contents/embedded.provisionprofile').read_bytes() != profile.read_bytes():
                raise ValueError('Safari bundle does not contain the selected provisioning profile.')
        prepared.append((bundle, profile, signing_entitlements))
    if verify:
        return
    # Validate both profiles before changing either bundle.
    for bundle, profile, entitlements in prepared:
        (bundle / 'Contents/embedded.provisionprofile').write_bytes(profile.read_bytes())
        with (app.parent / (bundle.name + '.entitlements')).open('wb') as output:
            plistlib.dump(entitlements, output)
    (app.parent / 'SafariVault.team').write_text(team)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error) if isinstance(error, ValueError) else 'Could not validate an Apple provisioning profile.')
