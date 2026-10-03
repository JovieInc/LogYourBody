import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

export const POLICY = Object.freeze({
  repository: 'JovieInc/LogYourBody', repositoryId: 998522682,
  project: 'prj_6seYBdTtY3TuFqrJek1puaFG6Trj', team: 'team_bpNDbti6srVLYPKdmQLu4UgT',
  name: 'log-your-body', maxMs: 20 * 60 * 1000,
});
const shaPattern = /^[a-f0-9]{40}$/;
const requireThat = (condition, message) => { if (!condition) throw new Error(message); };

export function targetForEvent(eventName, event) {
  requireThat(event.repository?.full_name === POLICY.repository && event.repository?.id === POLICY.repositoryId, 'Wrong repository');
  let sha, ref;
  if (eventName === 'pull_request') {
    const pr = event.pull_request;
    requireThat(pr?.base?.ref === 'main' && pr?.head?.repo?.id === POLICY.repositoryId, 'Unsupported PR base or fork');
    sha = pr.head.sha; ref = pr.head.ref;
  } else {
    requireThat(eventName === 'merge_group' && event.action === 'checks_requested', 'Unsupported event');
    const group = event.merge_group;
    requireThat(group?.base_ref === 'refs/heads/main' && /^refs\/heads\/gh-readonly-queue\/main\//.test(group?.head_ref), 'Wrong merge group');
    sha = group.head_sha; ref = group.head_ref.replace(/^refs\/heads\//, '');
  }
  requireThat(shaPattern.test(sha) && typeof ref === 'string' && ref.length > 0 && ref !== 'main', 'Invalid Preview target');
  return { sha, ref, eventName };
}

export function previewReceipt(deployment, target, now) {
  requireThat(typeof deployment.id === 'string' && /^dpl_[A-Za-z0-9]+$/.test(deployment.id), 'Invalid deployment ID');
  requireThat(deployment.projectId === POLICY.project && deployment.target === null, 'Wrong project or not Preview');
  const source = deployment.gitSource;
  requireThat(source?.type === 'github' && String(source.repoId) === String(POLICY.repositoryId) && source.sha === target.sha, 'Wrong Git source SHA or repository');
  requireThat(source.ref === target.ref || source.ref === target.sha, 'Wrong Git ref');
  requireThat(Number.isFinite(deployment.createdAt) && deployment.createdAt > 0 && deployment.createdAt <= now, 'Invalid creation time');
  if (['QUEUED', 'INITIALIZING', 'BUILDING'].includes(deployment.readyState)) return null;
  requireThat(deployment.readyState === 'READY', 'Preview did not succeed');
  requireThat(Number.isFinite(deployment.ready) && deployment.ready >= deployment.createdAt && deployment.ready <= now, 'Invalid ready time');
  requireThat(typeof deployment.url === 'string' && /^[a-z0-9-]+\.vercel\.app$/.test(deployment.url), 'Invalid deployment URL');
  return { schema: 1, repository: POLICY.repository, project: POLICY.project, environment: 'Preview',
    sha: target.sha, ref: target.ref, event: target.eventName, deploymentId: deployment.id,
    createdAt: deployment.createdAt, readyAt: deployment.ready, verifiedAt: now, url: `https://${deployment.url}` };
}

export function vercelClient(token, fetcher = fetch) {
  requireThat(typeof token === 'string' && token.length > 0, 'VERCEL_TOKEN is required');
  return async (method, path, body) => {
    requireThat(['GET', 'POST', 'PATCH'].includes(method) && path.startsWith('/v') && !path.includes('://'), 'Invalid API request');
    const url = new URL(path, 'https://api.vercel.com');
    url.searchParams.set('teamId', POLICY.team);
    const response = await fetcher(url, { method, redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    // Never include provider error bodies, headers, or credentials in logs.
    requireThat(response.ok, `Vercel API failed (${response.status})`);
    return response.json();
  };
}

export async function waitForPreview(target, api, { now = Date.now, sleep = ms => new Promise(r => setTimeout(r, ms)), maxMs = POLICY.maxMs, deploymentId } = {}) {
  requireThat(Number.isFinite(maxMs) && maxMs > 0 && maxMs <= POLICY.maxMs, 'Invalid time budget');
  const deadline = now() + maxMs;
  while (now() < deadline) {
    let id = deploymentId;
    if (!id) {
      const listing = await api('GET', `/v6/deployments?projectId=${POLICY.project}&meta-githubCommitSha=${target.sha}&limit=100`);
      requireThat(Array.isArray(listing.deployments), 'Invalid deployment listing');
      // Do not fall back to an older success after a newer attempt failed.
      id = listing.deployments[0]?.uid;
    }
    if (id) {
      requireThat(/^dpl_[A-Za-z0-9]+$/.test(id), 'Invalid listed deployment ID');
      const deployment = await api('GET', `/v13/deployments/${id}`);
      requireThat(deployment.id === id, 'Deployment identity mismatch');
      const receipt = previewReceipt(deployment, target, now());
      if (receipt) {
        requireThat(now() < deadline, 'Preview evidence arrived after deadline');
        return receipt;
      }
    }
    await sleep(Math.min(10000, Math.max(0, deadline - now())));
  }
  throw new Error('Preview evidence deadline exceeded');
}

export async function deployOnce(target, grant, ledger, api, options = {}) {
  const now = options.now ?? Date.now;
  requireThat(grant?.schema === 1 && /^[A-Za-z0-9_-]{8,100}$/.test(grant.id), 'Invalid grant');
  requireThat(grant.repository === POLICY.repository && grant.project === POLICY.project && grant.sha === target.sha && grant.ref === target.ref && grant.event === target.eventName, 'Grant target mismatch');
  requireThat(grant.environment === 'Preview' && grant.attempts === 1 && Number.isFinite(grant.maxMs) && grant.maxMs > 0 && grant.maxMs <= POLICY.maxMs && Number.isFinite(grant.expiresAt) && grant.expiresAt > now(), 'Invalid grant limits');
  const deadline = Math.min(now() + grant.maxMs, grant.expiresAt);
  await mkdir(ledger, { recursive: true });
  // Claim before POST. Ambiguous responses consume the grant; never retry creation.
  await writeFile(resolve(ledger, `${grant.id}.json`), JSON.stringify({ grant, claimedAt: now() }), { flag: 'wx', mode: 0o600 });
  requireThat(now() < deadline, 'Grant expired during claim; grant consumed');
  const result = await api('POST', '/v13/deployments', { name: POLICY.name, project: POLICY.project,
    gitSource: { type: 'github', repoId: POLICY.repositoryId, ref: target.ref, sha: target.sha } });
  requireThat(typeof result.id === 'string' && /^dpl_[A-Za-z0-9]+$/.test(result.id), 'Creation did not return a deployment ID; grant consumed');
  try {
    await writeFile(resolve(ledger, `${grant.id}.deployment.json`), JSON.stringify({ id: result.id, sha: target.sha }), { flag: 'wx', mode: 0o600 });
    return await waitForPreview(target, api, { ...options, maxMs: deadline - now(), deploymentId: result.id });
  } catch (error) {
    // Only this grant's deployment is canceled; no production or unrelated action.
    await api('PATCH', `/v12/deployments/${result.id}/cancel`).catch(() => {});
    throw error;
  }
}

export async function main(args, env = process.env) {
  const [mode, eventName, eventFile, grantFile, ledger] = args;
  requireThat(mode === 'verify' || mode === 'deploy', 'Expected verify or deploy');
  const target = targetForEvent(eventName, JSON.parse(await readFile(eventFile, 'utf8')));
  const api = vercelClient(env.VERCEL_TOKEN);
  let receipt;
  if (mode === 'deploy') {
    requireThat(grantFile && ledger, 'Deployment requires approved grant file and durable ledger');
    receipt = await deployOnce(target, JSON.parse(await readFile(grantFile, 'utf8')), ledger, api);
  } else receipt = await waitForPreview(target, api);
  await writeFile('preview-evidence.json', `${JSON.stringify(receipt, null, 2)}\n`);
  return receipt;
}

/* node:coverage disable */
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).then(receipt => console.log(JSON.stringify(receipt))).catch(error => {
    console.error(error.message); process.exitCode = 1;
  });
}
/* node:coverage enable */
