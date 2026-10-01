import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

function records(pages, key) {
  const list = Array.isArray(pages) ? pages : [pages];
  if (!list.length || list.some((page) => !Array.isArray(page?.[key]))) {
    throw new Error(`Missing ${key} metadata`);
  }
  return list.flatMap((page) => page[key]);
}

export function selectReleaseRun(pages, sha, repository, releaseEvent) {
  if (typeof sha !== 'string' || sha.length !== 40 || !/^[a-f0-9]{40}$/.test(sha)) throw new Error('Invalid source SHA');
  if (!['push', 'workflow_dispatch'].includes(releaseEvent)) throw new Error('Invalid release event');
  const runs = records(pages, 'workflow_runs');
  // Incomplete same-source records must not hide a newer main run and enable queue reuse.
  for (const run of runs) {
    if (!run || typeof run.head_sha !== 'string' || run.head_sha.length !== 40 || !/^[a-f0-9]{40}$/.test(run.head_sha)) throw new Error('Invalid run source metadata');
    if (run.head_sha !== sha) continue;
    const provenance = [
      [run.repository?.full_name, /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/],
      [run.path, /^\.github\/workflows\/[^/]+\.ya?ml$/],
      [run.event, /^[a-z][a-z0-9_]*$/],
      [run.head_branch, /^\S+$/],
    ];
    if (provenance.some(([value, format]) => typeof value !== 'string' || value.trim() !== value || !format.test(value))) {
      throw new Error('Missing or invalid exact-source CI provenance');
    }
  }
  const candidates = runs.filter((run) =>
    run.head_sha === sha && run.repository?.full_name === repository &&
    run.path === '.github/workflows/ci.yml' &&
    ((run.event === 'push' && run.head_branch === 'main') ||
      (run.event === 'merge_group' && run.head_branch?.startsWith('gh-readonly-queue/main/'))));
  for (const run of candidates) {
    if (!Number.isSafeInteger(run.id) || run.id <= 0 ||
        !Number.isSafeInteger(run.run_attempt) || run.run_attempt <= 0 ||
        !Number.isFinite(Date.parse(run.created_at))) {
      throw new Error('Invalid CI run identity');
    }
  }
  // A current main run must finish; an older queue result cannot replace it.
  const pushes = candidates.filter((run) => run.event === 'push');
  // A push-triggered release also waits when main CI has not been created yet.
  const eligible = pushes.length || releaseEvent === 'push' ? pushes : candidates;
  return eligible.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) ||
    b.id - a.id || b.run_attempt - a.run_attempt)[0] ?? null;
}

export function validateReleaseRun(run, pages, requiredChecks) {
  if (!run) return { status: 'pending', detail: 'No exact-source CI run yet' };
  const identity = `CI run ${run.id} (${run.event}, attempt ${run.run_attempt})`;
  if (run.status !== 'completed') return { status: 'pending', detail: `${identity} is ${run.status}` };
  if (run.conclusion !== 'success') return { status: 'failed', detail: `${identity} concluded ${run.conclusion}` };
  const jobs = records(pages, 'jobs');
  if (jobs.some((job) => job.run_id !== run.id || job.run_attempt !== run.run_attempt || job.head_sha !== run.head_sha)) {
    throw new Error('Job provenance differs from selected run/attempt/source');
  }
  const names = requiredChecks.split(',').map((name) => name.trim()).filter(Boolean);
  if (!names.includes('CI Summary')) throw new Error('CI Summary is required');
  for (const name of names) {
    const matches = jobs.filter((job) => job.name === name);
    if (matches.length !== 1) return { status: 'failed', detail: `${identity} has missing or ambiguous ${name}` };
    const job = matches[0];
    // The workflow may skip unchanged optional surfaces, but never its summary.
    if (job.status !== 'completed' ||
        (job.conclusion !== 'success' && !(name !== 'CI Summary' && job.conclusion === 'skipped'))) {
      return { status: 'failed', detail: `${identity}: ${name} is ${job.status}/${job.conclusion}` };
    }
  }
  return { status: 'passed', detail: `${identity} passed all required checks on ${run.head_sha}` };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [mode, sha, repository, releaseEvent, runsPath, requiredChecks] = process.argv.slice(2);
    const run = selectReleaseRun(JSON.parse(readFileSync(runsPath, 'utf8')), sha, repository, releaseEvent);
    if (mode === 'select') {
      if (run) process.stdout.write(String(run.id));
    } else if (mode === 'validate') {
      const result = validateReleaseRun(run, JSON.parse(readFileSync(0, 'utf8')), requiredChecks);
      console.log(result.detail);
      process.exitCode = result.status === 'passed' ? 0 : result.status === 'pending' ? 2 : 1;
    } else {
      throw new Error('Unknown validator mode');
    }
  } catch (error) {
    console.error(`Release CI evidence rejected: ${error.message}`);
    process.exitCode = 1;
  }
}
