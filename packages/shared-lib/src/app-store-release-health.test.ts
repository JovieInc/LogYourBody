import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));
function run(settings: Record<string, unknown> = {}) {
  const output = execFileSync(
    'ruby',
    [
      '-ropenssl',
      '-rtime',
      '.github/scripts/fixtures/app-store-release-health/run.rb',
      JSON.stringify(settings),
    ],
    { cwd: root, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 10_000 },
  );
  return JSON.parse(output.trim().split('\n').at(-1)!);
}
function mutations(result: ReturnType<typeof run>, host = 'api.appstoreconnect.apple.com') {
  return result.requests.filter(
    (r: { host: string; method: string }) => r.host === host && r.method !== 'GET',
  );
}

describe('App Store release health', () => {
  it('blocks an approved breached build before requesting release', () => {
    const result = run({ fixture: 'breached' });
    expect(mutations(result)).toEqual([]);
    expect(result.exit_code).toBe(1);
    expect(result.summary).toContain('BREACHED');
    expect(mutations(result, 'api.github.com')[0].body.title).toContain('1.3.0');
  });
});

describe('release and phased rollout fixture actions', () => {
  it('releases a healthy exact build only after both Sentry queries', () => {
    const result = run({ reverse_versions: true });
    expect(result.exit_code).toBe(0);
    expect(result.summary).toContain('HEALTHY');
    expect(mutations(result)).toMatchObject([
      { method: 'POST', path: '/v1/appStoreVersionReleaseRequests' },
    ]);
    const sessions = result.requests.filter((r: { host: string }) => r.host === 'sentry.io');
    expect(sessions).toHaveLength(2);
    expect(sessions[0].query).toContainEqual(['query', 'release:"ios-1.3.0 (130)"']);
    expect(sessions[1].query).toContainEqual(['query', 'release:"ios-1.2.0 (120)"']);
    for (const request of sessions) {
      expect(request.query).toContainEqual(['project', 'log-your-body-ios']);
      expect(request.query).toContainEqual(['environment', 'production']);
      expect(request.query).toContainEqual(['statsPeriod', '24h']);
      expect(request.query).toContainEqual(['field', 'crash_free_rate(user)']);
      expect(request.query).toContainEqual(['field', 'crash_free_rate(session)']);
    }
    expect(result.requests.indexOf(sessions[1])).toBeLessThan(
      result.requests.indexOf(mutations(result)[0]),
    );
    expect(mutations(result, 'api.github.com')).toEqual([]);
  });

  it.each(['READY_FOR_SALE', 'READY_FOR_DISTRIBUTION'])(
    'pauses a breached %s rollout and reopens its issue even when APP_VERSION points ahead',
    (state) => {
      const result = run({
        state,
        phase: 'ACTIVE',
        fixture: 'breached',
        app_version: '1.2.0',
        issue_state: 'closed',
      });
      expect(result.exit_code).toBe(1);
      expect(mutations(result)).toMatchObject([
        {
          method: 'PATCH',
          path: '/v1/appStoreVersionPhasedReleases/phase-new',
          body: {
            data: {
              type: 'appStoreVersionPhasedReleases',
              id: 'phase-new',
              attributes: { phasedReleaseState: 'PAUSED' },
            },
          },
        },
      ]);
      expect(mutations(result, 'api.github.com')).toMatchObject([
        {
          method: 'PATCH',
          path: '/repos/fixture/repo/issues/42',
          body: { state: 'open' },
        },
      ]);
      expect(result.summary).toContain('phased release PAUSED');
    },
  );

  it('blocks a regression that remains above the absolute floor', () => {
    const result = run({ session_rate: 0.996, regression_pp: 0.2 });
    expect(result.exit_code).toBe(1);
    expect(mutations(result)).toEqual([]);
    expect(result.summary).toContain('regressed 0.3 percentage points');
    expect(result.summary).not.toContain('below 99.5%');
  });

  it.each([
    { fixture: 'no-data' },
    { previous_fixture: 'no-data' },
    { no_previous: true },
    { missing_token: true },
    { sentry_status: 403 },
    { stale: true },
    { future: true },
    { response_release: 'ios-1.3.0 (wrong-build)' },
    { no_phase: true },
    { regression_pp: 'invalid' },
    { null_rate: true },
    { few_users: true },
    { missing_build: true },
    { phase_404: true },
  ])('makes missing/invalid health UNVERIFIED and blocks release: %j', (settings) => {
    const result = run(settings);
    expect(result.exit_code).toBe(1);
    expect(result.summary).toContain('UNVERIFIED');
    expect(mutations(result)).toEqual([]);
    expect(mutations(result, 'api.github.com')).toHaveLength(1);
    expect(result.summary).not.toContain('fixture-secret');
    expect(result.summary).not.toContain('fixture-gh-secret');
  });

  it('pauses an active rollout when health data disappears', () => {
    const result = run({ state: 'READY_FOR_SALE', phase: 'ACTIVE', fixture: 'no-data' });
    expect(result.exit_code).toBe(1);
    expect(result.summary).toContain('UNVERIFIED');
    expect(mutations(result)[0].body.data.attributes.phasedReleaseState).toBe('PAUSED');
  });

  it.each(['ACTIVE', 'PAUSED'])('keeps a healthy %s rollout unchanged', (phase) => {
    const result = run({ state: 'READY_FOR_SALE', phase });
    expect(result.exit_code).toBe(0);
    expect(result.summary).toContain('HEALTHY');
    expect(mutations(result)).toEqual([]);
  });

  it('never resumes an unhealthy paused rollout and updates its existing open issue', () => {
    const result = run({
      state: 'READY_FOR_SALE',
      phase: 'PAUSED',
      fixture: 'breached',
      issue_state: 'open',
    });
    expect(result.exit_code).toBe(1);
    expect(mutations(result)).toEqual([]);
    expect(mutations(result, 'api.github.com')).toHaveLength(1);
    expect(mutations(result, 'api.github.com')[0].method).toBe('PATCH');
  });

  it('still files remediation when the pause API fails', () => {
    const result = run({
      state: 'READY_FOR_SALE',
      phase: 'ACTIVE',
      fixture: 'breached',
      pause_status: 503,
    });
    expect(result.exit_code).toBe(1);
    expect(result.summary).toContain('Pause FAILED');
    expect(mutations(result, 'api.github.com')).toHaveLength(1);
  });

  it('pauses before filing and surfaces failed issue creation', () => {
    const result = run({
      state: 'READY_FOR_SALE',
      phase: 'ACTIVE',
      fixture: 'breached',
      issue_status: 403,
    });
    expect(result.exit_code).toBe(1);
    expect(result.summary).toContain('phased release PAUSED');
    expect(result.summary).toContain('Remediation issue FAILED');
  });

  it('requires the pause response to confirm PAUSED', () => {
    const result = run({
      state: 'READY_FOR_SALE',
      phase: 'ACTIVE',
      fixture: 'breached',
      pause_response: 'ACTIVE',
    });
    expect(result.exit_code).toBe(1);
    expect(result.summary).toContain('Pause FAILED: App Store Connect did not confirm PAUSED');
    expect(mutations(result, 'api.github.com')).toHaveLength(1);
  });

  it('keeps a known absolute breach visible when the comparison has no data', () => {
    const result = run({ fixture: 'breached', previous_fixture: 'no-data' });
    expect(result.summary).toContain('BREACHED');
    expect(result.exit_code).toBe(1);
    expect(mutations(result)).toEqual([]);
  });

  it('does not query Sentry or mutate ASC while waiting for review', () => {
    const result = run({ state: 'WAITING_FOR_REVIEW' });
    expect(result.exit_code).toBe(0);
    expect(mutations(result)).toEqual([]);
    expect(result.requests.filter((r: { host: string }) => r.host === 'sentry.io')).toEqual([]);
  });

  it('retains a mandatory pre-release health gate in the submission and monitor workflows', () => {
    const submit = readFileSync(`${root}/.github/workflows/ios-release-loop.yml`, 'utf8');
    expect(submit).toContain('automatic_release:false');
    expect(submit).not.toMatch(/automatic_release:\s*\n/);
    expect(submit).not.toContain('AUTOMATIC_RELEASE=');
    const monitor = readFileSync(
      `${root}/.github/workflows/ios-app-store-approved-release.yml`,
      'utf8',
    );
    expect(monitor).toContain("cron: '*/30 * * * *'");
    expect(monitor).toContain('issues: write');
    expect(monitor).toContain('SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}');
    expect(monitor).toContain('GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}');
    const ci = readFileSync(`${root}/.github/workflows/ci.yml`, 'utf8');
    expect(ci).toContain(
      'run: pnpm --filter @logyourbody/shared-lib exec vitest run src/app-store-release-health.test.ts',
    );
    const swift = readFileSync(
      `${root}/apps/ios/LogYourBody/Services/ErrorTrackingService.swift`,
      'utf8',
    );
    expect(swift).toContain('options.releaseName = "ios-\\(version) (\\(build))"');
  });
});
