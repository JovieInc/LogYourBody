"""Fail when an exported IPA embeds an extension whose version differs from the host app.

Apple rejects an upload when an appex CFBundleVersion or CFBundleShortVersionString
does not match the containing app (ITMS-90473). The release archive stamps both
values with xcargs; this check reads the exported IPA so a stale generated
Info.plist cannot ship.
"""
import argparse
import plistlib
import re
import sys
import tempfile
import zipfile
from pathlib import Path

BUILD_KEYS = ('CFBundleVersion', 'CFBundleShortVersionString')
BUILD_PATTERN = re.compile(r'\A\d+(?:\.\d+){0,2}\Z')
VERSION_PATTERN = re.compile(r'\A\d+\.\d+(?:\.\d+)?\Z')


def check_ipa(ipa_path, expected_build=None, expected_version=None):
    ipa_path = Path(ipa_path)
    if not ipa_path.is_file():
        return [f'IPA not found: {ipa_path}']
    with tempfile.TemporaryDirectory(prefix='lyb-ipa-versions-') as directory:
        try:
            payload = unzip_payload(ipa_path, Path(directory))
        except (OSError, zipfile.BadZipFile, ValueError) as error:
            return [f'Could not unzip {ipa_path.name}: {error}']
        return check_payload(payload, expected_build, expected_version)


def unzip_payload(ipa_path, destination):
    with zipfile.ZipFile(ipa_path) as archive:
        for info in archive.infolist():
            parts = Path(info.filename).parts
            if info.filename.startswith('/') or '..' in parts:
                raise ValueError(f'refusing unsafe IPA path: {info.filename}')
            archive.extract(info, destination)
    payload = destination / 'Payload'
    if not payload.is_dir():
        raise ValueError('IPA has no Payload directory')
    return payload


def check_payload(payload, expected_build=None, expected_version=None):
    errors = []
    errors.extend(validate_expected('expected build', expected_build, BUILD_PATTERN))
    errors.extend(validate_expected('expected marketing version', expected_version, VERSION_PATTERN))
    apps = sorted(path for path in payload.glob('*.app') if path.is_dir() and not path.is_symlink())
    if len(apps) != 1:
        return errors + [f'Expected one host app in Payload, found {len(apps)}']
    app = apps[0]
    host, host_errors = bundle_versions(app, app.name)
    errors.extend(host_errors)
    if host and expected_build is not None and host.get('CFBundleVersion') != expected_build:
        errors.append(
            f'{app.name} CFBundleVersion {host.get("CFBundleVersion")} != pinned {expected_build}'
        )
    if host and expected_version is not None and host.get('CFBundleShortVersionString') != expected_version:
        errors.append(
            f'{app.name} CFBundleShortVersionString {host.get("CFBundleShortVersionString")} '
            f'!= pinned {expected_version}'
        )
    appexes = sorted(
        path for path in app.rglob('*.appex') if path.is_dir() and not path.is_symlink()
    )
    for appex in appexes:
        versions, appex_errors = bundle_versions(appex, appex.name)
        errors.extend(appex_errors)
        if not host or not versions:
            continue
        for key in BUILD_KEYS:
            if versions.get(key) != host.get(key):
                errors.append(
                    f'{appex.name} {key} {versions.get(key)} != host {host.get(key)}'
                )
    if errors:
        return errors
    print(
        f'host {app.name} CFBundleVersion={host["CFBundleVersion"]} '
        f'CFBundleShortVersionString={host["CFBundleShortVersionString"]} appex={len(appexes)}'
    )
    return []


def validate_expected(label, value, pattern):
    if value is None:
        return []
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        return [f'{label} is not a bundle version: {value}']
    return []


def bundle_versions(bundle, label):
    plist_path = bundle / 'Info.plist'
    if plist_path.is_symlink() or not plist_path.is_file():
        return None, [f'{label} is missing Info.plist']
    try:
        with plist_path.open('rb') as handle:
            plist = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        return None, [f'{label} Info.plist could not be read: {error}']
    versions = {}
    errors = []
    for key in BUILD_KEYS:
        value = plist.get(key) if isinstance(plist, dict) else None
        if not isinstance(value, str) or not value.strip():
            errors.append(f'{label} is missing {key}')
            continue
        if '$(' in value or value.startswith('$'):
            errors.append(f'{label} {key} was not resolved: {value}')
            continue
        versions[key] = value
    return versions, errors


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', required=True, type=Path)
    parser.add_argument('--expected-build')
    parser.add_argument('--expected-version')
    args = parser.parse_args(argv)
    errors = check_ipa(args.ipa, args.expected_build, args.expected_version)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
