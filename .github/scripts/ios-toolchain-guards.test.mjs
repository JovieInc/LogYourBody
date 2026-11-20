import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (path) => readFileSync(join(root, path), 'utf8');
function sandbox(t) {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-376-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function command(path, source) {
  writeFileSync(path, source, { mode: 0o755 });
}
function run(script, args = [], env = {}) {
  const result = spawnSync('bash', [script, ...args], { encoding: 'utf8', env: { ...process.env, ...env } });
  assert.ifError(result.error);
  return { ...result, output: result.stdout + result.stderr };
}

function pinFixture(t, { installed = true, version = '27.1', sdk = '27.1' } = {}) {
  const dir = sandbox(t);
  const app = join(dir, 'Applications/Xcode_27.1.app');
  if (installed) mkdirSync(join(app, 'Contents/Developer'), { recursive: true });
  const bin = join(dir, 'bin');
  mkdirSync(bin);
  // Change only the fixed path in an isolated script copy, never the real host.
  const source = read('.github/scripts/pin-xcode-27.sh');
  assert.equal(source.split("readonly xcode_app='/Applications/Xcode_27.1.app'").length, 2);
  const script = join(dir, 'pin.sh');
  writeFileSync(script, source.replace("readonly xcode_app='/Applications/Xcode_27.1.app'", `readonly xcode_app='${app}'`));
  command(join(bin, 'xcodebuild'), `#!/bin/bash\nif [[ "$1" == -version ]]; then printf 'Xcode ${version}\\nBuild version fixture\\n'; else echo 'iOS fixture -sdk iphoneos${sdk}'; fi\n`);
  command(join(bin, 'xcrun'), `#!/bin/bash\nif [[ "$3" == --show-sdk-version ]]; then echo '${sdk}'; else echo '${app}/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS${sdk}.sdk'; fi\n`);
  command(join(bin, 'xcode-select'), '#!/bin/bash\necho /fixture/old-xcode\n');
  const envFile = join(dir, 'github-env');
  writeFileSync(envFile, '');
  return { script, envFile, app, env: { PATH: `${bin}:${process.env.PATH}`, GITHUB_ENV: envFile, DEVELOPER_DIR: '/fixture/old-xcode' } };
}

test('missing Xcode fails loudly without persisting a fallback', (t) => {
  const fixture = pinFixture(t, { installed: false });
  const result = run(fixture.script, [], fixture.env);
  assert.notEqual(result.status, 0);
  assert.match(result.output, /::error::Required Xcode 27.1 is missing/);
  assert.match(result.output, /runs-on was left unchanged on purpose/);
  assert.match(result.output, /xcode-27 \(not xlarge\)/);
  assert.match(result.output, /Current DEVELOPER_DIR=\/fixture\/old-xcode/);
  assert.match(result.output, /Available Xcode applications/);
  assert.equal(readFileSync(fixture.envFile, 'utf8'), '');
});

test('Xcode 27.1 and iphoneos27.x persist the exact pin and print evidence', (t) => {
  const fixture = pinFixture(t);
  const result = run(fixture.script, [], fixture.env);
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /Xcode 27.1/);
  assert.match(result.output, /Selected iPhone OS SDK: iphoneos27.1/);
  assert.equal(readFileSync(fixture.envFile, 'utf8'), `DEVELOPER_DIR=${fixture.app}/Contents/Developer\n`);
});

for (const [name, options] of [['26.x SDK', { sdk: '26.5' }], ['wrong Xcode at the pinned path', { version: '26.6' }]]) {
  test(`${name} is rejected even when the pinned directory exists`, (t) => {
    const fixture = pinFixture(t, options);
    const result = run(fixture.script, [], fixture.env);
    assert.notEqual(result.status, 0);
    assert.match(result.output, /::error::/);
    assert.equal(readFileSync(fixture.envFile, 'utf8'), '');
  });
}

function ipaFixture(t) {
  const dir = sandbox(t);
  for (const path of ['.github/scripts/verify-ios-ipa-min-sdk.sh', 'apps/ios/Scripts/verify-app-store-min-sdk.mjs', 'apps/ios/config/app-store-min-sdk.json']) {
    const target = join(dir, path);
    mkdirSync(dirname(target), { recursive: true });
    copyFileSync(join(root, path), target);
  }
  const artifacts = join(dir, 'artifacts');
  mkdirSync(artifacts);
  const bin = join(dir, 'bin');
  mkdirSync(bin);
  // Ubuntu has no Apple's plutil; emulate only the binary-to-XML conversion.
  if (process.platform !== 'darwin') command(join(bin, 'plutil'), `#!/usr/bin/env python3\nimport plistlib,sys\np=sys.argv[3]\nwith open(p,'rb') as f: data=plistlib.load(f)\nwith open(p,'wb') as f: plistlib.dump(data,f,fmt=plistlib.FMT_XML)\n`);
  return { dir, artifacts, script: join(dir, '.github/scripts/verify-ios-ipa-min-sdk.sh'), env: { PATH: `${bin}:${process.env.PATH}` } };
}
function ipa(fixture, name, sdk, plistPath = 'Payload/LogYourBody.app/Info.plist') {
  const result = spawnSync('python3', ['-c', 'import plistlib,sys,zipfile\nwith zipfile.ZipFile(sys.argv[1],"w") as z: z.writestr(sys.argv[2],plistlib.dumps({"DTSDKName":sys.argv[3]} if sys.argv[3] else {},fmt=plistlib.FMT_BINARY))', join(fixture.artifacts, name), plistPath, sdk], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
}

test('binary host plist in an IPA is checked successfully', (t) => {
  const fixture = ipaFixture(t);
  ipa(fixture, 'app.ipa', 'iphoneos27.1');
  const result = run(fixture.script, [fixture.artifacts], fixture.env);
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /OK:/);
});

for (const scenario of ['no IPA', 'multiple IPAs', 'no host plist', 'missing SDK key', 'below minimum', 'missing guard']) {
  test(`IPA verification fails closed: ${scenario}`, (t) => {
    const fixture = ipaFixture(t);
    if (scenario !== 'no IPA') ipa(fixture, 'app.ipa', scenario === 'missing SDK key' ? '' : scenario === 'below minimum' ? 'iphoneos0.1' : 'iphoneos27.1', scenario === 'no host plist' ? 'Payload/App.app/PlugIns/Widget.appex/Info.plist' : undefined);
    if (scenario === 'multiple IPAs') ipa(fixture, 'other.ipa', 'iphoneos27.1');
    if (scenario === 'missing guard') rmSync(join(fixture.dir, 'apps/ios/Scripts/verify-app-store-min-sdk.mjs'));
    const result = run(fixture.script, [fixture.artifacts], fixture.env);
    assert.notEqual(result.status, 0, result.output);
    assert.match(result.output, /::error/);
  });
}

function yaml(path) {
  const result = spawnSync('ruby', ['-rjson', '-ryaml', '-e', 'puts JSON.generate(YAML.load_file(ARGV.fetch(0)))', join(root, path)], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}
function steps(workflow, job) { return yaml(`.github/workflows/${workflow}.yml`).jobs[job].steps; }
function order(list, before, after) {
  const index = (pattern) => list.findIndex((step) => pattern.test(step.name || step.uses || ''));
  assert.ok(index(before) >= 0 && index(after) > index(before), `${before} must precede ${after}`);
}

test('diagnostic trust fence rejects a changed pin helper even at a clean candidate SHA', (t) => {
  const dir = sandbox(t);
  const body = steps('ios-ui-diagnostics', 'diagnostic').find((step) => step.name === 'Validate reviewed composed tooling before candidate execution').run;
  const source = body.split("<<'DIAGNOSTIC_TOOLING_PY'\n")[1].split('\nDIAGNOSTIC_TOOLING_PY')[0];
  const result = spawnSync('python3', ['-c', `
import hashlib,json,subprocess,sys
from pathlib import Path
data=json.load(sys.stdin)
namespace={'__name__':'reviewed_guard_fixture'}
exec(data['source'],namespace)
root=Path(data['dir']).resolve()
pin_name='.github/scripts/pin-xcode-27.sh'
pin=root/pin_name
pin.parent.mkdir(parents=True)
pin.write_text(data['pin'])
expected_pin=namespace['DEPENDENCIES'][pin_name]
assert hashlib.sha256(pin.read_bytes()).hexdigest()==expected_pin
audit=root/'scripts/ios/launch-quality-audit.sh'
audit.parent.mkdir(parents=True)
audit.write_text('# inert audit fixture\\n')
expected_audit=hashlib.sha256(audit.read_bytes()).hexdigest()
def git(*args):
    return subprocess.check_output(['git','-C',str(root),*args],text=True).strip()
git('init','-q')
def commit():
    git('add','.')
    git('-c','user.name=SDK guard fixture','-c','user.email=sdk-fixture@example.invalid','commit','-qm','Fixture candidate')
    return git('rev-parse','HEAD')
head=commit()
output=root.parent/(root.name+'-trust.json')
try:
    guard=namespace['validate_tooling']
    guard(root,head,expected_audit,{pin_name:expected_pin},output)
    assert output.exists()
    pin.write_text(data['pin']+'\\n# unreviewed candidate change\\n')
    head=commit()
    try:
        guard(root,head,expected_audit,{pin_name:expected_pin},output)
    except ValueError as error:
        assert 'reviewed dependency mismatch: '+pin_name in str(error)
        assert not output.exists()
    else:
        raise AssertionError('Changed candidate helper was admitted')
finally:
    output.unlink(missing_ok=True)
`], {
    encoding: 'utf8',
    input: JSON.stringify({ source, dir, pin: read('.github/scripts/pin-xcode-27.sh') }),
    // Fixture commits have no relationship to the user's signing configuration.
    env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' },
  });
  assert.equal(result.status, 0, result.stderr);
});

test('every composite consumer requests 27.1 and direct pins precede native tools', () => {
  const action = yaml('.github/actions/setup-ios-build/action.yml');
  assert.equal(action.inputs['xcode-version'].default, '27.1');
  assert.match(action.runs.steps[0].run, /pin-xcode-27\.sh/);
  assert.equal(action.runs.steps[0].if, undefined);
  for (const workflow of ['ios-quality', 'ios-unit', 'ios-release-loop', 'ios-testflight-deploy', 'deploy', 'ci', 'regenerate-certificates', 'codeql-analysis']) {
    const jobs = yaml(`.github/workflows/${workflow}.yml`).jobs;
    for (const job of Object.values(jobs)) for (const step of job.steps || []) {
      if (step.uses === './.github/actions/setup-ios-build') assert.equal(step.with['xcode-version'], '27.1', workflow);
      assert.doesNotMatch(step.uses || '', /setup-xcode/);
    }
  }
  order(steps('codeql-analysis', 'analyze'), /Pin Xcode/, /Initialize CodeQL/);
  order(steps('ios-ui-diagnostics', 'diagnostic'), /Select hosted Xcode/, /Run fixed seven-case diagnostic/);
  order(steps('ios-release-loop', 'bind-release-version'), /Pin Xcode/, /Extract version info/);
});

test('all three artifact paths are guarded between archive/download and upload', () => {
  const release = steps('ios-release-loop', 'build-release');
  order(release, /Archive and export/, /Verify App Store minimum SDK/);
  order(release, /Verify App Store minimum SDK/, /Upload build artifact/);
  const testflight = steps('ios-testflight-deploy', 'deploy-testflight');
  order(testflight, /Download build artifact/, /Verify App Store minimum SDK/);
  order(testflight, /Verify App Store minimum SDK/, /Upload to TestFlight/);
  const guard = testflight.find((step) => /Verify App Store minimum SDK/.test(step.name || ''));
  const upload = testflight.find((step) => step.name === 'Upload to TestFlight');
  assert.equal(guard.if, upload.if, 'resume-only distributes an existing build; it never uploads an IPA');
  const beta = steps('deploy', 'ios-beta');
  order(beta, /Archive beta/, /Verify App Store minimum SDK/);
  order(beta, /Verify App Store minimum SDK/, /Upload beta to TestFlight/);
  assert.match(beta.find((step) => step.name === 'Archive beta').run, /fastlane beta_archive/);
  assert.match(beta.find((step) => step.name === 'Upload beta to TestFlight').run, /fastlane beta_upload/);
});
