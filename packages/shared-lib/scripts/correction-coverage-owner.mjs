import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { postCoverageComment } from '../../../.github/scripts/lib/linear-correction-coverage.mjs';
import {
  detectorFromGithubEvent,
  remediationIntakeDisabled,
} from '../../../.github/scripts/remediation-signal.mjs';
import { renderCoverage, ROOT, runCoverage } from './correction-coverage.mjs';

export async function runCoverageOwnerLoop({
  env = process.env,
  eventName,
  event = {},
  root = ROOT,
  fetchImpl = fetch,
} = {}) {
  if (remediationIntakeDisabled(env)) return { ok: true, action: 'disabled' };
  // Reuse the main-only intake. Deploy adds no coverage evidence beyond CI.
  if (
    env.GITHUB_REF !== 'refs/heads/main' ||
    !detectorFromGithubEvent(eventName, event, env)?.provenance ||
    (eventName === 'workflow_run' && event.workflow_run?.name !== 'CI')
  ) {
    return { ok: true, action: 'skip', reason: 'no_verified_main_source' };
  }
  try {
    const report = runCoverage([], { root, env });
    const revision = execFileSync('git', ['rev-parse', 'HEAD'], {
      cwd: root,
      encoding: 'utf8',
    }).trim();
    const result = await postCoverageComment({
      revision,
      body: renderCoverage(report),
      apiKey: env.LINEAR_API_KEY,
      fetchImpl,
    });
    if (!result.ok) throw new Error(result.reason);
    return result;
  } catch (error) {
    const line = `LYB coverage owner loop did NOT post: ${error.message}`;
    if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${line}\n`);
    return { ok: false, reason: line };
  }
}
