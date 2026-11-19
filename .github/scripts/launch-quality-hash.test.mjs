// Contract for the Launch Quality declared-inputs hash and exact-hash receipt.
// A success receipt may be reused only for an unchanged content hash. Any
// declared-input change, a missing/invalid receipt, or the weekly canary
// runs the audit fully. Never weakens the audit and never changes runs-on.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../..');
const hashScript = path.join(scriptDir, 'launch-quality-hash.py');
const manifestPath = path.join(scriptDir, 'launch-quality-inputs.json');
const qualityWorkflow = fs.readFileSync(path.join(scriptDir, '../workflows/ios-quality.yml'), 'utf8');
const canaryWorkflow = fs.readFileSync(path.join(scriptDir, '../workflows/ios-launch-quality-canary.yml'), 'utf8');
const ciWorkflow = fs.readFileSync(path.join(scriptDir, '../workflows/ci.yml'), 'utf8');
const detectScript = fs.readFileSync(path.join(scriptDir, 'detect-changes.sh'), 'utf8');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

const gitEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));
Object.assign(gitEnv, {
  GIT_AUTHOR_NAME: 'ci',
  GIT_AUTHOR_EMAIL: 'ci@example.com',
  GIT_COMMITTER_NAME: 'ci',
  GIT_COMMITTER_EMAIL: 'ci@example.com',
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_CONFIG_GLOBAL: '/dev/null',
});

const git = (cwd, ...args) => execFileSync('git', args, { cwd, env: gitEnv, encoding: 'utf8' }).trim();

function jobBlock(workflow, name) {
  const start = workflow.indexOf(`\n  ${name}:\n`);
  assert.notEqual(start, -1, `workflow has no ${name} job`);
  const rest = workflow.slice(start + 1);
  const end = rest.slice(1).search(/\n {2}[A-Za-z0-9_-]+:\n/);
  return end === -1 ? rest : rest.slice(0, end + 1);
}

function copyEssential(destination) {
  const paths = [
    '.github/scripts/launch-quality-hash.py',
    '.github/scripts/launch-quality-inputs.json',
    '.github/scripts/launch-quality-hash.test.mjs',
    '.github/workflows/ios-quality.yml',
    '.github/workflows/ios-launch-quality-canary.yml',
    '.github/actions/setup-ios-build/action.yml',
    'scripts/ios/launch-quality-audit.sh',
    'apps/ios/Info.plist',
  ];
  for (const relative of paths) {
    const source = path.join(repoRoot, relative);
    const target = path.join(destination, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.cpSync(source, target);
  }
}

function initRepo() {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'lyb-377-hash-'));
  git(workspace, 'init', '-q');
  git(workspace, 'checkout', '-q', '-b', 'main');
  copyEssential(workspace);
  git(workspace, 'add', '-A');
  git(workspace, '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'base');
  return workspace;
}

function parseOutputs(stdout) {
  const values = {};
  for (const line of stdout.split('\n')) {
    const index = line.indexOf('=');
    if (index === -1) continue;
    const key = line.slice(0, index);
    if (['hash', 'reuse', 'reason', 'xcode-version', 'input-count', 'receipt-run-id', 'receipt-run-url', 'receipt-head-sha'].includes(key)) {
      values[key] = line.slice(index + 1);
    }
  }
  return values;
}

function runHash(cwd, args, env = {}) {
  const result = spawnSync('python3', [hashScript, ...args, '--root', cwd], {
    cwd,
    env: { ...process.env, ...gitEnv, ...env },
    encoding: 'utf8',
  });
  return result;
}

function writeGhStub(directory, handler) {
  const stub = path.join(directory, 'gh');
  const payloadPath = path.join(directory, 'gh-handler.json');
  fs.writeFileSync(payloadPath, JSON.stringify(handler));
  fs.writeFileSync(
    stub,
    `#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
handler = json.loads(Path(os.environ["LQ_GH_HANDLER"]).read_text())
args = sys.argv[1:]
if args[:1] != ["api"]:
    sys.stderr.write("unexpected gh invocation\\n")
    sys.exit(2)
route = args[1]
if route.startswith("repos/") and "actions/artifacts?" in route:
    sys.stdout.write(json.dumps(handler.get("list") or {"artifacts": []}))
    sys.exit(0)
if "/actions/artifacts/" in route and route.endswith("/zip"):
    data = Path(handler["zip"]).read_bytes()
    sys.stdout.buffer.write(data)
    sys.exit(0)
sys.stderr.write("unhandled route " + route + "\\n")
sys.exit(2)
`,
    { mode: 0o755 },
  );
  return stub;
}

async function writeReceiptZip(file, receipt) {
  // Minimal zip: use python in the test via spawn for reliability.
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lyb-377-zip-'));
  fs.writeFileSync(path.join(tmp, 'receipt.json'), JSON.stringify(receipt));
  execFileSync('python3', ['-c', `import zipfile; z=zipfile.ZipFile(${JSON.stringify(file)},'w'); z.write(${JSON.stringify(path.join(tmp, 'receipt.json'))}, 'receipt.json')`]);
  fs.rmSync(tmp, { recursive: true, force: true });
}

test('manifest globs cover the audit script, iOS sources, and the Xcode pin', () => {
  assert.equal(manifest.version, 1);
  for (const required of [
    'apps/ios/**',
    'scripts/ios/**',
    '.github/actions/setup-ios-build/action.yml',
    '.github/workflows/ios-quality.yml',
    '.github/scripts/launch-quality-hash.py',
    '.github/scripts/launch-quality-inputs.json',
  ]) {
    assert.ok(manifest.globs.includes(required), required);
  }
  assert.equal(manifest.xcodeVersionFrom.file, '.github/workflows/ios-quality.yml');
});

test('every path the launch-quality audit script references is a declared input', () => {
  const audit = fs.readFileSync(path.join(repoRoot, 'scripts/ios/launch-quality-audit.sh'), 'utf8');
  const referenced = new Set();
  const pattern = /\$ROOT_DIR\/([A-Za-z0-9_./-]+)/g;
  let match;
  while ((match = pattern.exec(audit))) {
    referenced.add(match[1]);
  }
  assert.ok(referenced.has('scripts/ios/launch-quality-evidence.py'));
  const matchesGlob = (file) => manifest.globs.some((glob) => {
    if (glob.endsWith('/**')) {
      const prefix = glob.slice(0, -3).replace(/\/$/, '');
      return file === prefix || file.startsWith(`${prefix}/`);
    }
    return file === glob;
  });
  const missing = [...referenced].filter((file) => !matchesGlob(file));
  assert.deepEqual(missing, [], `undeclared audit inputs: ${missing.join(', ')}`);
});

test('hash is stable, changes with iOS or Xcode inputs, and ignores undeclared files', () => {
  const workspace = initRepo();
  try {
    const first = parseOutputs(runHash(workspace, ['hash']).stdout);
    assert.match(first.hash, /^[0-9a-f]{64}$/);
    assert.equal(first['xcode-version'], 'latest-stable');
    const second = parseOutputs(runHash(workspace, ['hash']).stdout);
    assert.equal(second.hash, first.hash);

    fs.writeFileSync(path.join(workspace, 'README.md'), 'docs only\n');
    fs.mkdirSync(path.join(workspace, 'apps/web'), { recursive: true });
    fs.writeFileSync(path.join(workspace, 'apps/web/page.tsx'), 'export default function Page() { return null }');
    fs.mkdirSync(path.join(workspace, '.github/workflows'), { recursive: true });
    const ciPath = path.join(workspace, '.github/workflows/ci.yml');
    fs.writeFileSync(ciPath, 'name: CI\n');
    git(workspace, 'add', 'README.md', 'apps/web/page.tsx', '.github/workflows/ci.yml');
    git(workspace, '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'undeclared');
    const unchanged = parseOutputs(runHash(workspace, ['hash']).stdout);
    assert.equal(unchanged.hash, first.hash, 'undeclared files must not change the hash');

    fs.appendFileSync(path.join(workspace, 'apps/ios/Info.plist'), '<!-- changed -->\n');
    git(workspace, 'add', 'apps/ios/Info.plist');
    git(workspace, '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'ios');
    const iosChanged = parseOutputs(runHash(workspace, ['hash']).stdout);
    assert.notEqual(iosChanged.hash, first.hash);

    const qualityPath = path.join(workspace, '.github/workflows/ios-quality.yml');
    const quality = fs.readFileSync(qualityPath, 'utf8');
    fs.writeFileSync(qualityPath, quality.replace("xcode-version: 'latest-stable'", "xcode-version: '16.4'"));
    git(workspace, 'add', '.github/workflows/ios-quality.yml');
    git(workspace, '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'xcode');
    const xcodeChanged = parseOutputs(runHash(workspace, ['hash']).stdout);
    assert.notEqual(xcodeChanged.hash, iosChanged.hash);
    assert.equal(xcodeChanged['xcode-version'], '16.4');
  } finally {
    fs.rmSync(workspace, { recursive: true, force: true });
  }
});

test('lookup reuses only an exact-hash success receipt and fails closed otherwise', async () => {
  const workspace = initRepo();
  const tools = fs.mkdtempSync(path.join(os.tmpdir(), 'lyb-377-gh-'));
  try {
    const hashed = parseOutputs(runHash(workspace, ['hash']).stdout);
    const receipt = {
      schema: 'lyb-launch-quality-receipt-v1',
      hash: hashed.hash,
      verdict: 'success',
      headSha: 'a'.repeat(40),
      runId: '123',
      runUrl: 'https://github.com/JovieInc/LogYourBody/actions/runs/123',
    };
    const zipPath = path.join(tools, 'receipt.zip');
    await writeReceiptZip(zipPath, receipt);
    writeGhStub(tools, { list: { artifacts: [{ id: 9, name: `launch-quality-receipt-${hashed.hash}`, expired: false, created_at: '2026-11-19T00:00:00Z' }] }, zip: zipPath });

    const hit = parseOutputs(runHash(workspace, ['lookup'], {
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GH_TOKEN: 'test-token',
      LQ_GH: path.join(tools, 'gh'),
      LQ_GH_HANDLER: path.join(tools, 'gh-handler.json'),
      PATH: `${tools}:${process.env.PATH}`,
    }).stdout);
    assert.equal(hit.reuse, 'true');
    assert.equal(hit.reason, 'exact-hash-receipt');
    assert.equal(hit['receipt-run-id'], '123');

    const forced = parseOutputs(runHash(workspace, ['lookup'], {
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GH_TOKEN: 'test-token',
      FORCE_LAUNCH_QUALITY: '1',
      LQ_GH: path.join(tools, 'gh'),
      LQ_GH_HANDLER: path.join(tools, 'gh-handler.json'),
    }).stdout);
    assert.equal(forced.reuse, 'false');
    assert.equal(forced.reason, 'canary-or-forced-full');

    const failed = {
      ...receipt,
      verdict: 'failure',
    };
    const failedZip = path.join(tools, 'failed.zip');
    await writeReceiptZip(failedZip, failed);
    writeGhStub(tools, { list: { artifacts: [{ id: 9, name: `launch-quality-receipt-${hashed.hash}`, expired: false, created_at: '2026-11-19T00:00:00Z' }] }, zip: failedZip });
    const red = parseOutputs(runHash(workspace, ['lookup'], {
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GH_TOKEN: 'test-token',
      LQ_GH: path.join(tools, 'gh'),
      LQ_GH_HANDLER: path.join(tools, 'gh-handler.json'),
    }).stdout);
    assert.equal(red.reuse, 'false');

    const mismatched = { ...receipt, hash: '0'.repeat(64) };
    const mismatchZip = path.join(tools, 'mismatch.zip');
    await writeReceiptZip(mismatchZip, mismatched);
    writeGhStub(tools, { list: { artifacts: [{ id: 9, name: `launch-quality-receipt-${hashed.hash}`, expired: false, created_at: '2026-11-19T00:00:00Z' }] }, zip: mismatchZip });
    const wrong = parseOutputs(runHash(workspace, ['lookup'], {
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GH_TOKEN: 'test-token',
      LQ_GH: path.join(tools, 'gh'),
      LQ_GH_HANDLER: path.join(tools, 'gh-handler.json'),
    }).stdout);
    assert.equal(wrong.reuse, 'false');

    fs.appendFileSync(path.join(workspace, 'scripts/ios/launch-quality-audit.sh'), '# changed\n');
    git(workspace, 'add', 'scripts/ios/launch-quality-audit.sh');
    git(workspace, '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'audit script');
    const changed = parseOutputs(runHash(workspace, ['lookup'], {
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GH_TOKEN: 'test-token',
      LQ_GH: path.join(tools, 'gh'),
      LQ_GH_HANDLER: path.join(tools, 'gh-handler.json'),
    }).stdout);
    assert.equal(changed.reuse, 'false');
    assert.notEqual(changed.hash, hashed.hash);
  } finally {
    fs.rmSync(workspace, { recursive: true, force: true });
    fs.rmSync(tools, { recursive: true, force: true });
  }
});

test('lookup without a token or on a missing receipt runs fully (fail closed, job continues)', () => {
  const workspace = initRepo();
  try {
    const bare = parseOutputs(runHash(workspace, ['lookup']).stdout);
    assert.equal(bare.reuse, 'false');
    assert.equal(bare.reason, 'lookup-unavailable');
  } finally {
    fs.rmSync(workspace, { recursive: true, force: true });
  }
});

test('publish writes a success receipt for the current hash and refuses declared-input symlinks', () => {
  const workspace = initRepo();
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'lyb-377-pub-'));
  try {
    const published = runHash(workspace, ['publish', '--dir', out], {
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GITHUB_RUN_ID: '99',
      GITHUB_SERVER_URL: 'https://github.com',
    });
    assert.equal(published.status, 0, published.stderr);
    const receipt = JSON.parse(fs.readFileSync(path.join(out, 'receipt.json'), 'utf8'));
    const hashed = parseOutputs(runHash(workspace, ['hash']).stdout);
    assert.equal(receipt.schema, 'lyb-launch-quality-receipt-v1');
    assert.equal(receipt.verdict, 'success');
    assert.equal(receipt.hash, hashed.hash);
    assert.equal(receipt.runId, '99');

    fs.symlinkSync('Info.plist', path.join(workspace, 'apps/ios', 'linked-plist'));
    git(workspace, 'add', 'apps/ios/linked-plist');
    git(workspace, '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'symlink');
    const refused = runHash(workspace, ['publish', '--dir', path.join(out, 'nope')]);
    assert.notEqual(refused.status, 0);
    const lookup = parseOutputs(runHash(workspace, ['lookup'], {
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GH_TOKEN: 'test-token',
    }).stdout);
    assert.equal(lookup.reuse, 'false');
    assert.equal(lookup.reason, 'declared-symlink');
  } finally {
    fs.rmSync(workspace, { recursive: true, force: true });
    fs.rmSync(out, { recursive: true, force: true });
  }
});

test('ios-quality.yml reuses a receipt without weakening the audit or changing runs-on', () => {
  const quality = jobBlock(qualityWorkflow, 'quality');
  assert.match(qualityWorkflow, /force-full:\n(?: {8}.*\n)* {8}default: false/);
  assert.match(quality, /permissions:\n {6}contents: read\n {6}actions: read\n/);
  assert.match(
    quality,
    /runs-on: \$\{\{ !\(github\.event_name == 'workflow_dispatch' && startsWith\(github\.workflow_ref, format\('\{0\}\/\.github\/workflows\/ios-quality\.yml@', github\.repository\)\)\) && inputs\.mac-child && fromJSON\('\["self-hosted","macOS","ARM64","jovie-mac"\]'\) \|\| 'macos-15' \}\}/,
  );
  assert.match(quality, /name: Resolve Launch Quality input hash/);
  assert.match(quality, /python3 \.github\/scripts\/launch-quality-hash\.py lookup/);
  assert.match(quality, /FORCE_LAUNCH_QUALITY: \$\{\{ inputs\.force-full && '1' \|\| '0' \}\}/);
  assert.match(quality, /id: receipt/);
  assert.match(quality, /id: audit/);
  assert.match(
    quality,
    /name: Run launch quality audit\n(?: {8}.*\n)* {8}if: \$\{\{ steps\.receipt\.outputs\.reuse != 'true' \}\}/,
  );
  assert.match(quality, /run: bash scripts\/ios\/launch-quality-audit\.sh/);
  assert.doesNotMatch(quality, /continue-on-error:/);
  assert.match(quality, /xcode-version: 'latest-stable'/);
  assert.match(quality, /name: Publish Launch Quality receipt/);
  assert.match(quality, /launch-quality-receipt-\$\{\{ steps\.receipt\.outputs\.hash \}\}/);
  assert.match(quality, /retention-days: 90/);
});

test('weekly canary forces a full Launch Quality run and does not change runners', () => {
  assert.match(canaryWorkflow, /schedule:\n {4}- cron: '27 14 \* \* 1'/);
  assert.match(canaryWorkflow, /workflow_dispatch:/);
  assert.match(canaryWorkflow, /cancel-in-progress: false/);
  assert.match(canaryWorkflow, /uses: \.\/\.github\/workflows\/ios-quality\.yml/);
  assert.match(canaryWorkflow, /force-full: true/);
  assert.match(canaryWorkflow, /mac-first: false/);
  assert.doesNotMatch(canaryWorkflow, /runs-on:/);
  assert.doesNotMatch(canaryWorkflow, /continue-on-error:/);
});

test('CI runs the declared-inputs contract and detect-changes selects the new hash inputs', () => {
  assert.match(
    ciWorkflow,
    /node --test \.github\/scripts\/detect-changes\.test\.mjs \.github\/scripts\/detect-changes-signing\.test\.mjs \.github\/scripts\/launch-quality-hash\.test\.mjs/,
  );
  assert.ok(detectScript.includes('launch-quality-hash\\.py'));
  assert.ok(detectScript.includes('launch-quality-hash\\.test\\.mjs'));
  assert.ok(detectScript.includes('launch-quality-inputs\\.json'));
  assert.ok(detectScript.includes('ios-launch-quality-canary'));
});
