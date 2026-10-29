/**
 * ops.health/v1 identity receipt (contract: JovieInc/Jovie canon/OPS_HEALTH.md).
 * Unknown stays explicit: commitSha and deployedAt are null, never guessed, and
 * status is only `up` when the deployed commit is known.
 */
const SHA = /^[0-9a-f]{40}$/;

export function buildOpsHealth(env: Record<string, string | undefined>, now: number = Date.now()) {
  const sha = (env.VERCEL_GIT_COMMIT_SHA ?? '').trim().toLowerCase();
  const commitSha = SHA.test(sha) ? sha : null;
  const builtAt = Date.parse(env.OPS_BUILD_TIME ?? '');
  return {
    schema: 'ops.health/v1' as const,
    service: 'logyourbody-web',
    environment: env.VERCEL_ENV || 'unknown',
    commitSha,
    deployedAt: Number.isFinite(builtAt) ? new Date(builtAt).toISOString() : null,
    version: env.NEXT_PUBLIC_APP_VERSION || null,
    status: commitSha ? ('up' as const) : ('unknown' as const),
    checkedAt: new Date(now).toISOString(),
    dependencies: [] as never[],
  };
}
