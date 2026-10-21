// Bot-only refs must never reach the shared Vercel build queue or Actions.
//
// 2026-10-20: preserving dirty Gem worktrees pushed ~150 backup/gem/* branches
// here. Each queued a Vercel preview build on the team's shared build
// concurrency, starving Jovie staging until every canary timed out and
// production promotion stalled for hours. git.deploymentEnabled stops Vercel
// creating those deployments. Vercel matches its keys with minimatch, and a
// branch deploys if any matching rule is true, so no rule may re-enable them.
// `main: false` stays: production ships through deploy.yml's CLI deploy.
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const VERCEL_CONFIGS = ['vercel.json', 'apps/web/vercel.json'];
const EXCLUDED_PREFIXES = ['backup', 'archive', 'stash', 'gh-readonly-queue'];
const SAMPLE_REFS = EXCLUDED_PREFIXES.map(prefix => `${prefix}/gem/run-20261020/codex_some-lane`);
const WORKFLOWS_DIR = '.github/workflows';

// minimatch / GitHub filter semantics for these patterns: `**` spans slashes,
// `*` and `?` stay inside one segment.
export function globToRegExp(glob) {
  let source = '';
  for (let i = 0; i < glob.length; i++) {
    const char = glob[i];
    if (char === '*' && glob[i + 1] === '*') {
      source += '.*';
      i++;
    } else if (char === '*') source += '[^/]*';
    else if (char === '?') source += '[^/]';
    else source += char.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${source}$`);
}
const matches = (glob, ref) => globToRegExp(glob).test(ref);

export function vercelDeploys(config, ref) {
  const enabled = config.git?.deploymentEnabled;
  if (enabled === undefined) return true;
  if (typeof enabled === 'boolean') return enabled;
  const rules = Object.entries(enabled).filter(([glob]) => matches(glob, ref));
  if (rules.length === 0) return true;
  return rules.some(([, value]) => value === true);
}

const unquote = value => value.trim().replace(/^['"]|['"]$/g, '');
const inlineList = value =>
  value.trim().startsWith('[')
    ? value.trim().slice(1, -1).split(',').map(unquote).filter(Boolean)
    : [unquote(value)].filter(Boolean);

// Reads the top-level `on:` block of a workflow without a YAML dependency
// (this runs before pnpm install). Returns event -> { filter: string[] }.
export function workflowTriggers(text) {
  const lines = text.split('\n');
  const start = lines.findIndex(line => /^(?:on|'on'|"on"|true):/.test(line));
  if (start === -1) throw new Error('workflow has no on: block');
  const head = lines[start].replace(/^[^:]+:/, '').replace(/#.*$/, '').trim();
  if (head) return Object.fromEntries(inlineList(head).map(event => [event, {}]));
  const triggers = {};
  let event = null;
  let filter = null;
  for (const raw of lines.slice(start + 1)) {
    const line = raw.replace(/\s+#.*$/, '');
    if (!line.trim() || line.trim().startsWith('#')) continue;
    if (!/^\s/.test(line)) break;
    const indent = line.length - line.trimStart().length;
    const key = line.trim().match(/^([\w-]+):\s*(.*)$/);
    if (indent === 2 && key) {
      event = key[1];
      triggers[event] = {};
      filter = null;
    } else if (indent === 4 && key && event) {
      filter = key[1];
      triggers[event][filter] = key[2] ? inlineList(key[2]) : [];
    } else if (filter && event && line.trim().startsWith('- ')) {
      triggers[event][filter].push(unquote(line.trim().slice(2)));
    }
  }
  return triggers;
}

export function pushRuns(push, ref) {
  const branches = push.branches ?? [];
  const ignored = push['branches-ignore'] ?? [];
  if (branches.length === 0 && ignored.length === 0 && push.tags) return false;
  if (branches.length > 0) {
    return branches.some(glob => !glob.startsWith('!') && matches(glob, ref));
  }
  return !ignored.some(glob => matches(glob, ref));
}

test('glob and rule semantics match Vercel and Actions', () => {
  assert.equal(matches('backup/**', 'backup/gem/a/b'), true);
  assert.equal(matches('backup/*', 'backup/gem/a'), false);
  assert.equal(matches('backup/**', 'backups/x'), false);
  assert.equal(
    vercelDeploys({ git: { deploymentEnabled: { 'backup/**': false, '**': true } } }, 'backup/x'),
    true,
  );
  assert.deepEqual(
    workflowTriggers('on:\n  push:\n    branches: [main]\n  workflow_dispatch:\njobs: {}\n'),
    { push: { branches: ['main'] }, workflow_dispatch: {} },
  );
  assert.deepEqual(workflowTriggers('on: [push, pull_request]\n'), { push: {}, pull_request: {} });
  assert.equal(pushRuns({}, 'backup/x'), true);
  assert.equal(pushRuns({ 'branches-ignore': ['backup/**'] }, 'backup/x'), false);
});

for (const file of VERCEL_CONFIGS) {
  test(`${file} never deploys bot-only refs`, () => {
    const config = JSON.parse(readFileSync(file, 'utf8'));
    for (const prefix of EXCLUDED_PREFIXES) {
      assert.equal(config.git?.deploymentEnabled?.[`${prefix}/**`], false, `${file} must set ${prefix}/** to false`);
    }
    for (const ref of SAMPLE_REFS) {
      assert.equal(vercelDeploys(config, ref), false, `${file} would deploy ${ref}`);
    }
    assert.equal(vercelDeploys(config, 'feature/preview'), true, `${file} must keep PR previews`);
  });
}

test('no workflow runs on a push or creation of a bot-only ref', () => {
  const offenders = [];
  for (const name of readdirSync(WORKFLOWS_DIR).filter(n => /\.ya?ml$/.test(n))) {
    const on = workflowTriggers(readFileSync(join(WORKFLOWS_DIR, name), 'utf8'));
    if ('create' in on) offenders.push(`${name}: create`);
    if (!('push' in on)) continue;
    for (const ref of SAMPLE_REFS) {
      if (pushRuns(on.push, ref)) offenders.push(`${name}: push ${ref}`);
    }
  }
  assert.deepEqual(offenders, []);
});
