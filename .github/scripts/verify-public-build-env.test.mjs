import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkBundle, checkPulledEnv, isPlaceholder, parseEnv } from './verify-public-build-env.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const script = join(root, '.github/scripts/verify-public-build-env.mjs');
const workflow = readFileSync(join(root, '.github/workflows/deploy.yml'), 'utf8');
const GOOD_KEY = 'client-unit-test-not-a-real-key';
const goodEnv = `DATABASE_URL="postgres://example"\nNEXT_PUBLIC_STATSIG_CLIENT_KEY="${GOOD_KEY}"\nNEXT_PUBLIC_OTHER="ok"\n`;

function cli(args) {
  return spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
}

function tempDir(t) {
  const directory = mkdtempSync(join(tmpdir(), 'public-env-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test('accepts a pulled env with a real-looking Statsig client key', () => {
  assert.deepEqual(checkPulledEnv(goodEnv), []);
});

test('fails and names any NEXT_PUBLIC_* variable carrying the sensitive placeholder', () => {
  const failures = checkPulledEnv(`${goodEnv}NEXT_PUBLIC_API_URL="[SENSITIVE]"\nNEXT_PUBLIC_B=prefix-[sensitive]\nSECRET_TOKEN="[SENSITIVE]"\n`);
  assert.equal(failures.length, 2);
  assert.ok(failures.some((failure) => failure.includes('NEXT_PUBLIC_API_URL')));
  assert.ok(failures.some((failure) => failure.includes('NEXT_PUBLIC_B')));
  assert.ok(!failures.some((failure) => failure.includes('SECRET_TOKEN')), 'server-only variables are not browser-inlined');
});

test('fails when the Statsig client key is the sensitive placeholder, naming it once', () => {
  const failures = checkPulledEnv('NEXT_PUBLIC_STATSIG_CLIENT_KEY="[SENSITIVE]"\n');
  assert.equal(failures.length, 1);
  assert.match(failures[0], /^NEXT_PUBLIC_STATSIG_CLIENT_KEY /);
});

test('fails when the Statsig client key is missing or empty', () => {
  for (const contents of ['DATABASE_URL="x"\n', 'NEXT_PUBLIC_STATSIG_CLIENT_KEY=""\n', 'NEXT_PUBLIC_STATSIG_CLIENT_KEY=\n', 'NEXT_PUBLIC_STATSIG_CLIENT_KEY="  "\n', '']) {
    const failures = checkPulledEnv(contents);
    assert.equal(failures.length, 1, JSON.stringify(contents));
    assert.match(failures[0], /missing or empty/);
  }
});

test('fails on placeholder Statsig client keys', () => {
  for (const value of ['placeholder', 'PLACEHOLDER', 'changeme', 'xxx', 'XXXXXXXX', 'undefined', 'null', '<key>', '[redacted]', '${STATSIG_KEY}']) {
    const failures = checkPulledEnv(`NEXT_PUBLIC_STATSIG_CLIENT_KEY="${value}"\n`);
    assert.equal(failures.length, 1, value);
    assert.match(failures[0], /placeholder/);
  }
  assert.equal(isPlaceholder(GOOD_KEY), false);
});

test('the last duplicate definition of the Statsig key wins, like dotenv', () => {
  assert.deepEqual(checkPulledEnv(`NEXT_PUBLIC_STATSIG_CLIENT_KEY="changeme"\nNEXT_PUBLIC_STATSIG_CLIENT_KEY="${GOOD_KEY}"\n`), []);
  assert.equal(checkPulledEnv(`NEXT_PUBLIC_STATSIG_CLIENT_KEY="${GOOD_KEY}"\nNEXT_PUBLIC_STATSIG_CLIENT_KEY="changeme"\n`).length, 1);
});

test('parses quoted, unquoted, exported and commented lines', () => {
  assert.deepEqual(parseEnv('# c\nexport A="1"\nB=2\nC=\'3\'\n\nnot a line\n'), [['A', '1'], ['B', '2'], ['C', '3']]);
});

test('failure output never contains the value', () => {
  const secret = 'SUPER-SECRET-PLACEHOLDER-[SENSITIVE]-VALUE';
  const failures = checkPulledEnv(`NEXT_PUBLIC_LEAK="${secret}"\nNEXT_PUBLIC_STATSIG_CLIENT_KEY="${GOOD_KEY}"\n`);
  assert.equal(failures.length, 1);
  assert.ok(!failures[0].includes('SUPER-SECRET'));
});

test('bundle scan fails on the placeholder in client JS and reports file and count only', (t) => {
  const directory = tempDir(t);
  mkdirSync(join(directory, 'chunks'));
  writeFileSync(join(directory, 'chunks', 'app.js'), `x({clientKey:"[SENSITIVE]"});y("[SENSITIVE]")`);
  writeFileSync(join(directory, 'chunks', 'clean.js'), 'x({clientKey:"client-abc"})');
  const failures = checkBundle([directory], { cwd: directory });
  assert.equal(failures.length, 1);
  assert.match(failures[0], /chunks\/app\.js/);
  assert.match(failures[0], /2 time\(s\)/);
  assert.ok(!failures[0].includes('clientKey'));
});

test('bundle scan passes clean output and refuses to pass when nothing was scanned', (t) => {
  const directory = tempDir(t);
  writeFileSync(join(directory, 'app.js'), 'x({clientKey:"client-abc"})');
  assert.deepEqual(checkBundle([directory]), []);
  assert.equal(checkBundle([join(directory, 'missing')]).length, 1);
  assert.equal(checkBundle([directory, join(directory, 'missing')]).length, 1, 'every directory is required');
  const empty = join(directory, 'empty');
  mkdirSync(empty);
  assert.match(checkBundle([empty])[0], /no files to scan/);
});

test('CLI exits non-zero with ::error:: annotations and zero when clean', (t) => {
  const directory = tempDir(t);
  const bad = join(directory, 'bad.env');
  const good = join(directory, 'good.env');
  writeFileSync(bad, 'NEXT_PUBLIC_STATSIG_CLIENT_KEY="[SENSITIVE]"\n');
  writeFileSync(good, goodEnv);
  const failed = cli(['env', bad]);
  assert.equal(failed.status, 1);
  assert.match(failed.stderr, /::error::NEXT_PUBLIC_STATSIG_CLIENT_KEY/);
  assert.equal(cli(['env', good]).status, 0);
  assert.equal(cli(['env', join(directory, 'absent.env')]).status, 1);
  assert.equal(cli([]).status, 1);
  writeFileSync(join(directory, 'a.js'), '"[SENSITIVE]"');
  assert.equal(cli(['bundle', directory]).status, 1);
});

test('deploy.yml runs the guard after vercel pull and before build, then scans built output before deploy', () => {
  const index = (needle) => {
    const position = workflow.indexOf(needle);
    assert.notEqual(position, -1, needle);
    return position;
  };
  const pull = index('vercel@latest pull');
  const envGuard = index('verify-public-build-env.mjs env .vercel/.env.production.local');
  const migrations = index('db:apply:neon');
  const vercelBuild = index('vercel@latest build --prod');
  const bundleGuard = index('verify-public-build-env.mjs bundle');
  const deploy = index('vercel@latest deploy --prebuilt');
  assert.ok(pull < envGuard && envGuard < migrations && migrations < vercelBuild);
  assert.ok(vercelBuild < bundleGuard && bundleGuard < deploy);
  assert.match(workflow, /verify-public-build-env\.mjs bundle \.vercel\/output\/static/);
  const guardSteps = workflow.split('\n').filter((line) => line.includes('verify-public-build-env.mjs'));
  assert.ok(guardSteps.every((line) => !/continue-on-error|\|\|\s*true/.test(line)));
  assert.doesNotMatch(workflow, /continue-on-error/);
});
