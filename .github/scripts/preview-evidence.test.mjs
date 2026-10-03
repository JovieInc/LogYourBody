import assert from 'node:assert/strict';
import report from './preview-coverage-reporter.mjs';
import test from 'node:test';
import { mkdtemp, readFile, writeFile, rm, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { POLICY, targetForEvent, previewReceipt, waitForPreview, deployOnce, vercelClient, main } from './preview-evidence.mjs';

const sha = 'a'.repeat(40), groupSha = 'b'.repeat(40);
const repo = { full_name: POLICY.repository, id: POLICY.repositoryId };
const pr = { repository: repo, pull_request: { base: { ref: 'main' }, head: { sha, ref: 'fix/example', repo } } };
const group = { repository: repo, action: 'checks_requested', merge_group: { base_ref: 'refs/heads/main', head_ref: `refs/heads/gh-readonly-queue/main/pr-1100-${groupSha}`, head_sha: groupSha } };
const target = targetForEvent('pull_request', pr);
const at = 10000;
const ready = (t = target) => ({ id: 'dpl_test123', projectId: POLICY.project, target: null, readyState: 'READY',
  gitSource: { type: 'github', repoId: POLICY.repositoryId, sha: t.sha, ref: t.ref }, createdAt: 100, ready: 200, url: 'example.vercel.app' });
const grant = (t = target) => ({ schema: 1, id: 'grant_test_123', repository: POLICY.repository, project: POLICY.project, sha: t.sha, ref: t.ref,
  event: t.eventName, environment: 'Preview', attempts: 1, maxMs: 500, expiresAt: at + 1000 });
const clone = x => structuredClone(x);

async function temporary(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'lyb-preview-test-'));
  try { return await fn(dir); } finally { await rm(dir, { recursive: true, force: true }); }
}

test('PR head differs from GitHub test merge SHA; merge groups use combined SHA', () => {
  assert.equal(target.sha, sha);
  const t = targetForEvent('merge_group', group);
  assert.equal(t.sha, groupSha);
  assert.equal(t.ref, group.merge_group.head_ref.slice(11));
  for (const [kind, input] of [
    ['push', pr], ['pull_request', {}], ['pull_request', { ...pr, repository: { ...repo, id: 1 } }],
    ['pull_request', { ...pr, pull_request: null }],
    ['pull_request', { ...pr, pull_request: { ...pr.pull_request, base: { ref: 'dev' } } }],
    ['pull_request', { ...pr, pull_request: { ...pr.pull_request, head: { ...pr.pull_request.head, repo: { id: 1 } } } }],
    ['merge_group', { ...group, action: 'destroyed' }], ['merge_group', { ...group, merge_group: {} }],
    ['merge_group', { ...group, merge_group: { ...group.merge_group, head_ref: 'refs/heads/fake' } }],
  ]) assert.throws(() => targetForEvent(kind, input));
  for (const fields of [{ sha: 'short' }, { ref: 'main' }, { ref: '' }, { ref: 3 }]) {
    const p = clone(pr); Object.assign(p.pull_request.head, fields);
    assert.throws(() => targetForEvent('pull_request', p));
  }
});

test('receipt rejects wrong project, environment, repository, SHA, ref, state, time and URL', () => {
  const success = previewReceipt(ready(), target, at);
  assert.equal(success.sha, sha); assert.equal(success.deploymentId, 'dpl_test123');
  const exactRef = ready(); exactRef.gitSource.ref = sha;
  assert.equal(previewReceipt(exactRef, target, at).sha, sha);
  for (const state of ['QUEUED', 'INITIALIZING', 'BUILDING']) assert.equal(previewReceipt({ ...ready(), readyState: state }, target, at), null);
  for (const fields of [{ id: null }, { id: '../bad' }, { projectId: 'wrong' }, { target: 'production' }, { target: undefined },
    { gitSource: null }, { readyState: 'ERROR' }, { readyState: 'CANCELED' }, { readyState: 'unknown' },
    { createdAt: null }, { createdAt: 0 }, { createdAt: at + 1 }, { ready: null }, { ready: 99 }, { ready: at + 1 },
    { url: null }, { url: 'example.vercel.app.evil.com' }]) assert.throws(() => previewReceipt({ ...ready(), ...fields }, target, at));
  for (const fields of [{ type: 'gitlab' }, { repoId: 1 }, { sha: groupSha }, { ref: 'other' }]) {
    const d = ready(); Object.assign(d.gitSource, fields);
    assert.throws(() => previewReceipt(d, target, at));
  }
});

test('API binds canonical host/team, disallows redirects and sanitizes failures', async () => {
  assert.throws(() => vercelClient(''));
  const calls = [];
  const api = vercelClient('secret-test', async (url, options) => { calls.push([url, options]); return { ok: true, json: async () => ({ ok: 1 }) }; });
  assert.deepEqual(await api('GET', '/v6/deployments'), { ok: 1 });
  await api('POST', '/v13/deployments', { project: POLICY.project });
  assert.equal(calls[0][0].origin, 'https://api.vercel.com');
  assert.equal(calls[0][0].searchParams.get('teamId'), POLICY.team);
  assert.equal(calls[0][1].redirect, 'error');
  assert.equal(calls[1][1].body, JSON.stringify({ project: POLICY.project }));
  for (const [method, path] of [['DELETE', '/v1/x'], ['GET', 'https://evil.example'], ['GET', '/v1/https://evil.example']]) await assert.rejects(api(method, path));
  await assert.rejects(vercelClient('secret', async () => ({ ok: false, status: 403 }))('GET', '/v1/x'), /^Error: Vercel API failed \(403\)$/);
  await assert.rejects(vercelClient('secret', async () => { throw new Error('network'); })('GET', '/v1/x'), /network/);
});

test('poller waits for latest exact deployment and never falls back after a failure', async () => {
  let now = at, listings = 0, reads = 0;
  const receipt = await waitForPreview(target, async (_, path) => {
    if (path.startsWith('/v6/')) { listings++; return { deployments: listings === 1 ? [] : [{ uid: 'dpl_test123' }] }; }
    reads++; return { ...ready(), readyState: reads === 1 ? 'BUILDING' : 'READY' };
  }, { now: () => now, sleep: async ms => { now += ms; }, maxMs: 50000 });
  assert.equal(receipt.sha, sha); assert.equal(reads, 2);
  await assert.rejects(waitForPreview(target, async (_, path) => path.startsWith('/v6/')
    ? { deployments: [{ uid: 'dpl_failed' }, { uid: 'dpl_test123' }] }
    : { ...ready(), id: 'dpl_failed', readyState: 'ERROR' }, { now: () => at }), /did not succeed/);
  for (const listing of [{}, { deployments: [{ uid: '../bad' }] }]) await assert.rejects(waitForPreview(target, async () => listing, { now: () => at }));
  await assert.rejects(waitForPreview(target, async () => ready(), { now: () => at, deploymentId: 'dpl_other' }), /identity mismatch/);
  for (const maxMs of [0, POLICY.maxMs + 1, "500", NaN]) await assert.rejects(waitForPreview(target, async () => {}, { maxMs }), /time budget/);
  await assert.rejects(waitForPreview(target, async () => ({ deployments: [] }), { maxMs: 1 }), /deadline/);
  let clock = at;
  await assert.rejects(waitForPreview(target, async () => { clock += 2; return ready(); },
    { now: () => clock, deploymentId: 'dpl_test123', maxMs: 1 }), /after deadline/);
});

test('one-use deployment path covers both PR and real event-shaped merge-group SHA without production target', async () => temporary(async dir => {
  for (const t of [target, targetForEvent('merge_group', group)]) {
    const g = { ...grant(t), id: `grant_${t.eventName}` }, calls = [];
    const api = async (method, path, body) => { calls.push({ method, path, body }); return method === 'POST' ? { id: 'dpl_test123' } : ready(t); };
    const receipt = await deployOnce(t, g, dir, api, { now: () => at });
    assert.equal(receipt.sha, t.sha);
    assert.deepEqual(calls[0].body.gitSource, { type: 'github', repoId: POLICY.repositoryId, ref: t.ref, sha: t.sha });
    assert.equal(calls[0].body.target, undefined);
    assert.equal(JSON.parse(await readFile(join(dir, `${g.id}.json`))).grant.sha, t.sha);
    await assert.rejects(deployOnce(t, g, dir, api, { now: () => at }), /EEXIST/);
    assert.equal(calls.filter(c => c.method === 'POST').length, 1);
  }
}));

test('invalid or expired grants never invoke deployment API', async () => temporary(async dir => {
  const invalid = [null, { schema: 1, id: '../bad' }, ...[
    { repository: 'other' }, { project: 'other' }, { sha: groupSha }, { ref: 'other' }, { event: 'merge_group' },
    { environment: 'production' }, { attempts: 2 }, { maxMs: 0 }, { maxMs: "500" }, { maxMs: POLICY.maxMs + 1 }, { expiresAt: at }, { expiresAt: null },
  ].map(fields => ({ ...grant(), ...fields }))];
  for (const g of invalid) await assert.rejects(deployOnce(target, g, dir, async () => assert.fail('must not call API'), { now: () => at }));
}));

test('ambiguous creation consumes grant; terminal error/deadline cancel only returned deployment', async () => temporary(async dir => {
  let posts = 0;
  const api = async () => { posts++; throw new Error('ambiguous'); };
  await assert.rejects(deployOnce(target, grant(), dir, api, { now: () => at }), /ambiguous/);
  await assert.rejects(deployOnce(target, grant(), dir, api, { now: () => at }), /EEXIST/);
  assert.equal(posts, 1);
  await assert.rejects(deployOnce(target, { ...grant(), id: 'no_deploy_id' }, dir, async () => ({}), { now: () => at }), /grant consumed/);
  for (const scenario of ['error', 'timeout', 'cancel-error', 'expired-during-create']) {
    let now = at; const canceled = [];
    const transport = async (method, path) => {
      if (method === 'POST') { if (scenario === 'expired-during-create') now += 2000; return { id: 'dpl_test123' }; }
      if (method === 'PATCH') { canceled.push(path); if (scenario === 'cancel-error') throw new Error('cancel failed'); return {}; }
      return { ...ready(), readyState: scenario === 'timeout' ? 'BUILDING' : 'ERROR' };
    };
    await assert.rejects(deployOnce(target, { ...grant(), id: `grant_${scenario}` }, dir, transport, { now: () => now, sleep: async ms => { now += ms; } }));
    assert.deepEqual(canceled, ['/v12/deployments/dpl_test123/cancel']);
  }
}));

test('CLI verify and deploy exercise real file inputs/output with fake transport only', async () => temporary(async dir => {
  const originalFetch = globalThis.fetch, cwd = process.cwd();
  try {
    process.chdir(dir);
    await writeFile('event.json', JSON.stringify(pr));
    await writeFile('grant.json', JSON.stringify({ ...grant(), expiresAt: Date.now() + 10000 }));
    globalThis.fetch = async (url, options) => ({ ok: true, json: async () => url.pathname === '/v6/deployments'
      ? { deployments: [{ uid: 'dpl_test123' }] } : options.method === 'POST' ? { id: 'dpl_test123' } : ready() });
    await main(['verify', 'pull_request', 'event.json'], { VERCEL_TOKEN: 'fake' });
    assert.equal(JSON.parse(await readFile('preview-evidence.json')).sha, sha);
    await main(['deploy', 'pull_request', 'event.json', 'grant.json', join(dir, 'ledger')], { VERCEL_TOKEN: 'fake' });
    await assert.rejects(main(['deploy', 'pull_request', 'event.json'], { VERCEL_TOKEN: 'fake' }), /grant file/);
    await assert.rejects(main(['other']), /Expected/);
    await assert.rejects(main(['verify', 'pull_request', 'missing'], {}));
  } finally { globalThis.fetch = originalFetch; process.chdir(cwd); }
}));


test('grant expiring during ledger claim cannot POST', async () => temporary(async dir => {
  let reads = 0, posts = 0;
  const now = () => ++reads >= 4 ? at + 2000 : at;
  await assert.rejects(deployOnce(target, grant(), dir, async () => { posts++; }, { now }), /expired during claim/);
  assert.equal(posts, 0);
  assert.equal(JSON.parse(await readFile(join(dir, `${grant().id}.json`))).grant.sha, sha);
}));

test('deployment receipt write failure cancels only the created deployment', async () => temporary(async dir => {
  const g = grant();
  await mkdir(join(dir, `${g.id}.deployment.json`));
  const calls = [];
  await assert.rejects(deployOnce(target, g, dir, async (method, path) => {
    calls.push([method, path]); return { id: 'dpl_test123' };
  }, { now: () => at }), /EEXIST|EISDIR/);
  assert.deepEqual(calls, [['POST', '/v13/deployments'], ['PATCH', '/v12/deployments/dpl_test123/cancel']]);
}));


test('coverage gate rejects missing, malformed, failing and below-threshold execution reports', async () => {
  const file = { path: '/repo/preview-evidence.mjs', totalLineCount: 130, totalBranchCount: 82, totalFunctionCount: 10,
    coveredLinePercent: 100, coveredBranchPercent: 100, coveredFunctionPercent: 100 };
  const coverage = f => ({ type: 'test:coverage', data: { summary: { files: [f] } } });
  const collect = async events => { let text = ''; for await (const item of report(events)) text += item; return text; };
  assert.match(await collect([{ type: 'test:pass', data: { name: 'behavior' } }, coverage(file)]), /coverage/);
  for (const events of [[], [coverage({ ...file, path: '/wrong.mjs' })],
    [coverage({ ...file, coveredLinePercent: undefined })],
    ...['totalLineCount', 'totalBranchCount', 'totalFunctionCount'].flatMap(key => [undefined, NaN, 0, -1, 0.5].map(value => [coverage({ ...file, [key]: value })])),
    ...[{ coveredLinePercent: 94 }, { coveredBranchPercent: 89 }, { coveredFunctionPercent: 99 }].map(x => [coverage({ ...file, ...x })]),
    [{ type: 'test:fail', data: { name: 'behavior' } }, coverage(file)]]) await assert.rejects(collect(events));
});
