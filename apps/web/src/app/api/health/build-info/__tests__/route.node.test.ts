/** @jest-environment node */

import { buildOpsHealth } from '@/lib/ops-health';

const SHA = 'a'.repeat(40);
const NOW = Date.parse('2026-10-28T12:00:00.000Z');

describe('ops.health/v1 build-info', () => {
  it('reports the deployed commit and build time when known', () => {
    const body = buildOpsHealth(
      {
        VERCEL_GIT_COMMIT_SHA: SHA,
        VERCEL_ENV: 'production',
        NEXT_PUBLIC_APP_VERSION: '2025.06.36',
        OPS_BUILD_TIME: '2026-10-28T11:00:00.000Z',
      },
      NOW,
    );
    expect(body).toMatchObject({
      schema: 'ops.health/v1',
      service: 'logyourbody-web',
      environment: 'production',
      commitSha: SHA,
      deployedAt: '2026-10-28T11:00:00.000Z',
      status: 'up',
      checkedAt: '2026-10-28T12:00:00.000Z',
    });
  });

  it('keeps unknown explicit: no commit means unknown status, never up', () => {
    const body = buildOpsHealth({ VERCEL_GIT_COMMIT_SHA: 'abc1234' }, NOW);
    expect(body.commitSha).toBeNull();
    expect(body.deployedAt).toBeNull();
    expect(body.status).toBe('unknown');
    expect(body.environment).toBe('unknown');
  });
});
