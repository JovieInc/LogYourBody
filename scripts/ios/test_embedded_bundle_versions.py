"""A mismatched embedded extension must fail the exported-IPA version check."""
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKER = Path(__file__).with_name('check_embedded_bundle_versions.py')
HOST_BUILD = '20261101140020'
HOST_VERSION = '1.2.0'
STALE_BUILD = '20251126162826'


def write_plist(path, build, version, fmt=plistlib.FMT_BINARY):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('wb') as handle:
        plistlib.dump(
            {
                'CFBundleIdentifier': 'com.logyourbody.app',
                'CFBundleShortVersionString': version,
                'CFBundleVersion': build,
            },
            handle,
            fmt=fmt,
        )


def make_ipa(directory, host, extensions, fmt=plistlib.FMT_BINARY):
    stage = directory / 'stage'
    app = stage / 'Payload' / 'LogYourBody.app'
    write_plist(app / 'Info.plist', host[0], host[1], fmt)
    for name, build, version in extensions:
        write_plist(app / 'PlugIns' / name / 'Info.plist', build, version, fmt)
    ipa = directory / 'LogYourBody.ipa'
    with zipfile.ZipFile(ipa, 'w') as archive:
        for path in stage.rglob('*'):
            if path.is_file():
                archive.write(path, path.relative_to(stage).as_posix())
    return ipa


def make_appex_without_plist(directory):
    stage = directory / 'stage'
    app = stage / 'Payload' / 'LogYourBody.app'
    write_plist(app / 'Info.plist', HOST_BUILD, HOST_VERSION)
    appex = app / 'PlugIns' / 'LogYourBodyRestTimer.appex'
    appex.mkdir(parents=True)
    (appex / 'PkgInfo').write_bytes(b'APPL????')
    ipa = directory / 'LogYourBody.ipa'
    with zipfile.ZipFile(ipa, 'w') as archive:
        for path in stage.rglob('*'):
            if path.is_file():
                archive.write(path, path.relative_to(stage).as_posix())
    return ipa


def run_checker(ipa, expected_build=None, expected_version=None):
    command = [sys.executable, str(CHECKER), '--ipa', str(ipa)]
    if expected_build is not None:
        command.extend(['--expected-build', expected_build])
    if expected_version is not None:
        command.extend(['--expected-version', expected_version])
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    return completed.returncode, completed.stdout + completed.stderr


def expect_ok(name, code, output, accepted):
    if code != 0:
        raise SystemExit(f'{name} should pass\n{output}')
    accepted.append(name)


def expect_fail(name, code, output, needles, rejected):
    missing = [needle for needle in needles if needle not in output]
    if code == 0 or missing:
        raise SystemExit(f'{name} should fail mentioning {missing or needles}\n{output}')
    rejected.append(name)


def check_source_wiring():
    workflow = (ROOT / '.github/workflows/ios-release-loop.yml').read_text()
    for needle in (
        'check_embedded_bundle_versions.py',
        'RELEASE_BUILD_NUMBER:',
        'RELEASE_MARKETING_VERSION:',
        '--expected-build',
        '--expected-version',
    ):
        if needle not in workflow:
            raise SystemExit(f'release workflow is missing {needle}')
    if 'PlistBuddy' in workflow:
        raise SystemExit('release workflow still edits one Info.plist with PlistBuddy')
    fastfile = (ROOT / 'apps/ios/fastlane/Fastfile.release').read_text()
    for needle in ('CURRENT_PROJECT_VERSION=#{build_number}', 'MARKETING_VERSION=#{marketing_version}'):
        if needle not in fastfile:
            raise SystemExit(f'release lane is missing {needle}')
    with (ROOT / 'apps/ios/LogYourBody/Info.plist').open('rb') as handle:
        host = plistlib.load(handle)
    if host.get('CFBundleVersion') != '$(CURRENT_PROJECT_VERSION)':
        raise SystemExit('host Info.plist CFBundleVersion is not $(CURRENT_PROJECT_VERSION)')
    if host.get('CFBundleShortVersionString') != '$(MARKETING_VERSION)':
        raise SystemExit('host Info.plist CFBundleShortVersionString is not $(MARKETING_VERSION)')
    with (ROOT / 'apps/ios/LogYourBodyWidget/Info.plist').open('rb') as handle:
        widget = plistlib.load(handle)
    for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
        if key in widget:
            raise SystemExit(f'extension Info.plist hardcodes {key}')


def main():
    check_source_wiring()
    accepted = []
    rejected = []
    with tempfile.TemporaryDirectory(prefix='lyb-embedded-versions-') as directory:
        root = Path(directory)
        cases = {
            'matching-appex': make_ipa(
                root / 'matching',
                (HOST_BUILD, HOST_VERSION),
                [('LogYourBodyRestTimer.appex', HOST_BUILD, HOST_VERSION)],
            ),
            'matching-xml': make_ipa(
                root / 'xml',
                (HOST_BUILD, HOST_VERSION),
                [('LogYourBodyRestTimer.appex', HOST_BUILD, HOST_VERSION)],
                fmt=plistlib.FMT_XML,
            ),
            'no-appex': make_ipa(root / 'empty', (HOST_BUILD, HOST_VERSION), []),
            'mismatched-build': make_ipa(
                root / 'stale-build',
                (HOST_BUILD, HOST_VERSION),
                [('LogYourBodyRestTimer.appex', STALE_BUILD, HOST_VERSION)],
            ),
            'mismatched-marketing-version': make_ipa(
                root / 'stale-version',
                (HOST_BUILD, HOST_VERSION),
                [('LogYourBodyRestTimer.appex', HOST_BUILD, '1.0')],
            ),
            'unresolved-placeholder': make_ipa(
                root / 'placeholder',
                ('$(CURRENT_PROJECT_VERSION)', '$(MARKETING_VERSION)'),
                [('LogYourBodyRestTimer.appex', '$(CURRENT_PROJECT_VERSION)', '$(MARKETING_VERSION)')],
            ),
            'missing-appex-plist': make_appex_without_plist(root / 'missing-plist'),
            'host-differs-from-pin': make_ipa(root / 'unstamped', (STALE_BUILD, HOST_VERSION), []),
        }
        for name in ('matching-appex', 'matching-xml', 'no-appex'):
            code, output = run_checker(cases[name], HOST_BUILD, HOST_VERSION)
            expect_ok(name, code, output, accepted)
        code, output = run_checker(cases['mismatched-build'], HOST_BUILD, HOST_VERSION)
        expect_fail(
            'mismatched-build',
            code,
            output,
            ['LogYourBodyRestTimer.appex', 'CFBundleVersion', STALE_BUILD, HOST_BUILD],
            rejected,
        )
        code, output = run_checker(cases['mismatched-marketing-version'], HOST_BUILD, HOST_VERSION)
        expect_fail(
            'mismatched-marketing-version',
            code,
            output,
            ['LogYourBodyRestTimer.appex', 'CFBundleShortVersionString', '1.0', HOST_VERSION],
            rejected,
        )
        code, output = run_checker(cases['unresolved-placeholder'])
        expect_fail(
            'unresolved-placeholder',
            code,
            output,
            ['was not resolved', '$(CURRENT_PROJECT_VERSION)'],
            rejected,
        )
        code, output = run_checker(cases['missing-appex-plist'], HOST_BUILD, HOST_VERSION)
        expect_fail(
            'missing-appex-plist',
            code,
            output,
            ['LogYourBodyRestTimer.appex', 'Info.plist'],
            rejected,
        )
        code, output = run_checker(cases['host-differs-from-pin'], HOST_BUILD, HOST_VERSION)
        expect_fail(
            'host-differs-from-pin',
            code,
            output,
            ['CFBundleVersion', STALE_BUILD, HOST_BUILD],
            rejected,
        )
    print(json.dumps({'accepted': accepted, 'rejected': rejected}))


if __name__ == '__main__':
    main()
