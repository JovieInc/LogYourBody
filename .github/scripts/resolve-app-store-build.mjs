import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// App Store promotion must resolve an attested TestFlight build, never dispatch HEAD.
export function resolveAppStoreBuild(
  env,
  run = (command, args) => execFileSync(command, args, { encoding: 'utf8' }).trim(),
) {
  const build = env.BUILD_NUMBER || '';
  if (!/^\d+(?:\.\d+){0,2}$/.test(build)) {
    throw new Error('build_number is required and must be a CFBundleVersion');
  }
  if (env.PAYWALL_VERIFIED_BUILD_NUMBER !== build) {
    throw new Error(
      'paywall_verified_build_number must equal build_number after purchase and restore pass',
    );
  }
  if (env.GITHUB_REF !== 'refs/heads/main')
    throw new Error('App Store promotion must run from main');
  const repository = env.GITHUB_REPOSITORY;
  if (!/^[\w-]+\/[\w.-]+$/.test(repository || '')) throw new Error('Invalid repository');
  const server = env.GITHUB_SERVER_URL;
  if (!server) throw new Error('GITHUB_SERVER_URL is required');
  const refs = run('git', [
    'ls-remote',
    '--tags',
    'origin',
    `refs/tags/ios-v*-testflight.${build}*`,
  ]);
  const tags = new Map();
  for (const line of refs.split('\n')) {
    const match = line.match(
      /^([0-9a-f]{40})\s+refs\/tags\/(ios-v(\d+\.\d+(?:\.\d+)?)-testflight\.([\d.]+))(\^\{\})?$/,
    );
    if (!match || match[4] !== build) continue;
    const [, sha, tag, version, , peeled] = match;
    if (peeled || !tags.has(tag)) tags.set(tag, { tag, version, commit: sha });
  }
  if (tags.size !== 1)
    throw new Error('Expected exactly one TestFlight release tag for build_number');
  const selected = [...tags.values()][0];
  const api = (path, ...args) => JSON.parse(run('gh', ['api', path, ...args]));
  const release = api(`repos/${repository}/releases/tags/${selected.tag}`);
  if (release.draft || release.tag_name !== selected.tag)
    throw new Error('Published TestFlight release evidence is required');
  const body = release.body || '';
  if (
    !body.includes(`**Build Number**: ${build}\n`) ||
    !body.includes('**Deployment**: testflight\n') ||
    !body.includes(`**Commit**: ${selected.commit}\n`)
  ) {
    throw new Error('TestFlight release evidence does not match the selected build and tag commit');
  }
  const runPrefix = `${server}/${repository}/actions/runs/`;
  const runId = body.split(runPrefix)[1]?.match(/^([1-9]\d*)\)/)?.[1];
  if (!runId) throw new Error('TestFlight release must link its producing run');
  const sourceRun = api(`repos/${repository}/actions/runs/${runId}`);
  if (
    sourceRun.head_sha !== selected.commit ||
    sourceRun.head_branch !== 'main' ||
    sourceRun.path !== '.github/workflows/ios-release-loop.yml' ||
    sourceRun.status !== 'completed' ||
    sourceRun.conclusion !== 'success'
  ) {
    throw new Error(
      'TestFlight producing run must be successful on main at the release-tag commit',
    );
  }
  const jobs = api(
    `repos/${repository}/actions/runs/${runId}/jobs?per_page=100`,
    '--paginate',
    '--slurp',
  ).flatMap((page) => page.jobs);
  const deployed = jobs.some(
    (job) =>
      job.name.startsWith('Deploy to TestFlight / ') &&
      job.conclusion === 'success' &&
      ['Upload to TestFlight', 'Wait for processing and assign groups'].every((name) =>
        job.steps?.some((step) => step.name === name && step.conclusion === 'success'),
      ),
  );
  if (!deployed)
    throw new Error('Producing run has no successful TestFlight upload and processing receipt');
  return { ...selected, build_number: build, testflight_run: `${runPrefix}${runId}` };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const selected = resolveAppStoreBuild(process.env);
    appendFileSync(
      process.env.GITHUB_OUTPUT,
      Object.entries(selected)
        .map(([key, value]) => `${key}=${value}\n`)
        .join(''),
    );
    console.log(
      `Promoting TestFlight ${selected.version} (${selected.build_number}) at ${selected.commit} from ${selected.testflight_run}`,
    );
  } catch (error) {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  }
}
