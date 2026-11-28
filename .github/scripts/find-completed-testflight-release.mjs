import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { commitFromLsRemote, releaseTagName } from './ios-release-tag.mjs';

const run = (command, args) =>
  execFileSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 30_000,
  }).trim();

function readRelease(repository, tag) {
  try {
    return JSON.parse(run('gh', ['api', `repos/${repository}/releases/tags/${tag}`]));
  } catch (error) {
    if (/\(HTTP 404\)\s*$/.test(error.stderr ?? '')) return null;
    throw new Error(`Cannot verify published TestFlight receipt for ${tag}`);
  }
}

export function findCompletedRelease({ version, sha, repository, server }, listRefs, getRelease) {
  const prefix = releaseTagName({
    version,
    buildNumber: '00000000000000',
    deploymentType: 'testflight',
  }).slice(0, -14);
  if (!/^[0-9a-f]{40}$/.test(sha) || !/^[\w-]+\/[\w.-]+$/.test(repository || '') || !server) {
    throw new Error('Missing release commit or repository identity');
  }

  const refs = listRefs(`refs/tags/${prefix}*`);
  const tags = new Set(refs.split('\n').map((line) => line.split(/\s+/)[1]
    ?.replace(/^refs\/tags\//, '').replace(/\^\{\}$/, '')));
  for (const tag of [...tags].filter(Boolean).sort().reverse()) {
    const build = tag.slice(prefix.length);
    if (!tag.startsWith(prefix) || !/^\d{14}$/.test(build)) continue;
    if (commitFromLsRemote(refs, tag) !== sha) continue;

    // Tags are pinned before upload. The workflow publishes a release only
    // after TestFlight has processed the build and assigned the tester groups.
    const release = getRelease(repository, tag);
    if (release == null) continue;
    const lines = (release.body ?? '').split('\n');
    const runBase = `${server}/${repository}/actions/runs/`;
    const runPrefix = `- **Workflow**: [View Run](${runBase}`;
    const runId = lines.find((line) => line.startsWith(runPrefix))?.slice(runPrefix.length)
      .match(/^([1-9]\d*)\)$/)?.[1];
    if (
      release.tag_name === tag &&
      release.draft === false &&
      release.prerelease === true &&
      lines.includes(`**Build Number**: ${build}`) &&
      lines.includes('**Deployment**: testflight') &&
      lines.includes(`**Version**: ios-v${version}`) &&
      lines.includes(`- **Commit**: ${sha}`) &&
      runId
    ) {
      return { tag, build, url: `${runBase}${runId}` };
    }
  }
  return null;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const existing = findCompletedRelease(
      {
        version: process.argv[2],
        sha: process.env.GITHUB_SHA,
        repository: process.env.GITHUB_REPOSITORY,
        server: process.env.GITHUB_SERVER_URL,
      },
      (pattern) => run('git', ['ls-remote', '--tags', 'origin', pattern]),
      readRelease,
    );
    appendFileSync(process.env.GITHUB_OUTPUT, `already_deployed=${Boolean(existing)}\n`);
    if (existing) console.log(`TestFlight already deployed ${existing.tag} at ${process.env.GITHUB_SHA} (${existing.url})`);
  } catch (error) {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  }
}
