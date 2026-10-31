import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { checkHealth, fileRemediation, releaseName } from './app-store-release-health.mjs';

const candidate = { version: '1.3.0', build: '203' };
const previous = { version: '1.2.0', build: '202' };
const now = Date.parse('2026-10-31T10:41:00Z');
const env = { SENTRY_AUTH_TOKEN: 'fixture-secret' };
const fixture = (release, users = 0.999, sessions = 0.999) => ({
  start: '2026-10-30T10:00:00.000Z',
  end: '2026-10-31T10:00:00.000Z',
  groups: [
    {
      by: { release },
      totals: {
        'sum(session)': 1000,
        'count_unique(user)': 100,
        'crash_free_rate(user)': users,
        'crash_free_rate(session)': sessions,
      },
    },
  ],
});
async function check(transform = (body) => body) {
  const calls = [];
  const report = await checkHealth(
    { candidate, previous },
    {
      env,
      now,
      fetchImpl: async (url, options) => {
        calls.push({ url, options });
        const release = url.searchParams.get('query').slice(9, -1);
        return {
          status: 200,
          json: async () => transform(fixture(release), release === releaseName(candidate)),
        };
      },
    },
  );
  return { report, calls };
}

test('healthy exact-build fixture passes both floors and the previous-version comparison', async () => {
  const { report, calls } = await check();
  assert.equal(report.status, 'HEALTHY');
  assert.deepEqual(report.reasons, []);
  assert.equal(report.current.release, 'ios-1.3.0 (203)');
  assert.equal(calls.length, 2);
  for (const { url, options } of calls) {
    assert.equal(url.protocol, 'https:');
    assert.equal(url.hostname, 'sentry.io');
    assert.equal(url.searchParams.get('project'), 'log-your-body-ios');
    assert.equal(url.searchParams.get('environment'), 'production');
    assert.deepEqual(url.searchParams.getAll('field'), [
      'sum(session)',
      'count_unique(user)',
      'crash_free_rate(user)',
      'crash_free_rate(session)',
    ]);
    assert.equal(options.headers.Authorization, 'Bearer fixture-secret');
    assert.equal(options.redirect, 'error');
  }
});

for (const field of ['crash_free_rate(user)', 'crash_free_rate(session)']) {
  test(`breached fixture blocks on ${field} independently`, async () => {
    const { report } = await check((body, current) => {
      if (current) body.groups[0].totals[field] = 0.99;
      return body;
    });
    assert.equal(report.status, 'BREACHED');
    assert.match(report.reasons.join(' '), /below 99.50%/);
  });
  test(`relative comparison in ${field} allows exactly 0.20 points and detects a larger drop`, async () => {
    const { report } = await check((body, current) => {
      body.groups[0].totals[field] = current ? 0.998 : 1;
      // Exactly 0.2 percentage points is allowed.
      return body;
    });
    assert.equal(report.status, 'HEALTHY');
    // A larger drop breaches while still above the absolute floor.
    const { evaluateHealth } = await import('./app-store-release-health.mjs');
    const metric = field.includes('user') ? 'crashFreeUsers' : 'crashFreeSessions';
    const relative = evaluateHealth({ ...report.current, [metric]: 0.9979 }, report.previous);
    assert.match(relative.reasons.join(' '), /regressed more than/);
  });
}

for (const [name, transform] of [
  ['no data', () => ({ start: fixture('').start, end: fixture('').end, groups: [] })],
  [
    'wrong build',
    (body) => {
      body.groups[0].by.release = 'ios-1.3.0 (999)';
      return body;
    },
  ],
  ['stale window', (body) => ({ ...body, end: '2026-09-01T00:00:00Z' })],
  [
    'null rates',
    (body) => {
      body.groups[0].totals['crash_free_rate(user)'] = null;
      return body;
    },
  ],
  [
    'percentage instead of fraction',
    (body) => {
      body.groups[0].totals['crash_free_rate(user)'] = 99.9;
      return body;
    },
  ],
  [
    'insufficient sample',
    (body) => {
      body.groups[0].totals['count_unique(user)'] = 2;
      return body;
    },
  ],
  [
    'zero sessions',
    (body) => {
      body.groups[0].totals['sum(session)'] = 0;
      return body;
    },
  ],
]) {
  test(`${name} fixture is UNVERIFIED`, async () =>
    assert.equal((await check(transform)).report.status, 'UNVERIFIED'));
}

test('missing credentials, baseline and network/API/JSON failures are UNVERIFIED', async () => {
  for (const options of [
    { env: {} },
    {
      fetchImpl: async () => {
        throw new Error('secret network detail');
      },
    },
    { fetchImpl: async () => ({ status: 403 }) },
    { fetchImpl: async () => ({ status: 429 }) },
    {
      fetchImpl: async () => ({
        status: 200,
        json: async () => {
          throw new Error('secret body');
        },
      }),
    },
  ]) {
    const report = await checkHealth({ candidate, previous }, { env, now, ...options });
    assert.equal(report.status, 'UNVERIFIED');
    assert.doesNotMatch(JSON.stringify(report), /fixture-secret|secret body|secret network/);
  }
  const report = await checkHealth(
    { candidate },
    {
      env,
      now,
      fetchImpl: async () => ({ status: 200, json: async () => fixture(releaseName(candidate)) }),
    },
  );
  assert.equal(report.status, 'UNVERIFIED');
  assert.equal(report.current.release, releaseName(candidate));
});

test('known breach still blocks when previous-version health is missing', async () => {
  const { report } = await check((body, current) =>
    current ? fixture(releaseName(candidate), 0.9) : { ...body, groups: [] },
  );
  assert.equal(report.status, 'BREACHED');
});

test('remediation reuses Linear upsert with terminal reopen and one stable per-version fingerprint', async () => {
  const { report } = await check((body) => fixture(body.groups[0].by.release, 0.9));
  assert.equal((await fileRemediation(report, { env: {} })).ok, false);
  for (const terminal of [false, true]) {
    const calls = [];
    const label = { id: 'label', name: 'remediation:app-store-health-1.3.0' };
    const issue = {
      id: 'issue',
      identifier: 'LYB-fixture',
      url: 'https://example.com/LYB-fixture',
    };
    const result = await fileRemediation(
      { ...report, action: 'Phased rollout PAUSED' },
      {
        env: {
          LINEAR_API_KEY: 'linear-fixture',
          GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
          GITHUB_RUN_ID: '123',
        },
        fetchImpl: async (_url, options) => {
          const request = JSON.parse(options.body);
          calls.push(request);
          let data;
          if (request.query.includes('teams('))
            data = { teams: { nodes: [{ id: 'team', key: 'LYB' }] } };
          else if (request.query.includes('FindRemediationIssue'))
            data = {
              team: {
                states: { nodes: [{ id: 'todo', name: 'Todo', type: 'unstarted' }] },
                labels: { nodes: [label] },
              },
              issues: {
                nodes: terminal
                  ? [{ ...issue, state: { type: 'completed' }, labels: { nodes: [label] } }]
                  : [],
              },
            };
          else if (request.query.includes('CreateDedupedLinearIssue'))
            data = { issueCreate: { success: true, issue } };
          else if (request.query.includes('UpdateDedupedLinearIssue'))
            data = { issueUpdate: { success: true, issue } };
          else assert.fail(`Unexpected Linear operation: ${request.query}`);
          return { ok: true, status: 200, text: async () => JSON.stringify({ data }) };
        },
      },
    );
    assert.equal(result.ok, true);
    assert.equal(result.action, terminal ? 'updated' : 'created');
    const mutation = calls.at(-1).variables;
    assert.equal(terminal ? mutation.input.stateId : mutation.stateId, 'todo');
    assert.match(
      terminal ? mutation.input.description : mutation.description,
      /Phased rollout PAUSED/,
    );
    assert.equal(result.reopened ?? false, terminal);
    assert.match(JSON.stringify(calls[1].variables), /remediation:app-store-health-1.3.0/);
  }
});

test('actual submission lane rejects automatic release and defaults to manual release', () => {
  const fastfile = readFileSync(
    new URL('../../apps/ios/fastlane/Fastfile.release', import.meta.url),
    'utf8',
  );
  const lane = fastfile.match(/ {2}lane :submit_app_store do \|options\|[\s\S]*?\n {2}end/)?.[0];
  assert.ok(lane);
  const script = `
    require 'json'
    module UI
      def self.user_error!(message); raise message; end
    end
    def lane(*, &block); $lane = block; end
    def setup_app_store_connect_api; end
    def upload_to_app_store(**options); $uploads << options; end
    eval(STDIN.read)
    results = [nil, false, "false", true, "true"].map do |flag|
      $uploads = []
      error = nil
      begin
        $lane.call(automatic_release: flag, submit_for_review: true, phased_release: true)
      rescue => exception
        error = exception.message
      end
      { uploads: $uploads, error: error }
    end
    puts JSON.generate(results)
  `;
  const results = JSON.parse(
    execFileSync('ruby', ['-e', script], { input: lane, encoding: 'utf8' }),
  );
  for (const result of results.slice(0, 3)) {
    assert.equal(result.error, null);
    assert.equal(result.uploads[0].automatic_release, false);
    assert.equal(result.uploads[0].phased_release, true);
  }
  for (const result of results.slice(3)) {
    assert.match(result.error, /bypasses release health/);
    assert.deepEqual(result.uploads, []);
  }
});

test('Ruby monitor fixtures cover release, pause, no-data and failures through the real entrypoint', () => {
  const output = execFileSync(
    'ruby',
    [new URL('./release-approved-app-store-version-test.rb', import.meta.url).pathname],
    { encoding: 'utf8', timeout: 20_000 },
  );
  assert.match(output, /0 failures, 0 errors/);
});

test('submission and monitoring wiring cannot bypass the gate', () => {
  const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
  const workflow = read('../workflows/ios-release-loop.yml');
  assert.match(
    workflow,
    /AUTOMATIC_RELEASE="\$\{\{ github.event.inputs.automatic_release \|\| 'false' \}\}"/,
  );
  assert.match(workflow, /automatic_release:[\s\S]*?default: false/);
  const monitor = read('../workflows/ios-app-store-approved-release.yml');
  assert.match(monitor, /SENTRY_AUTH_TOKEN: \$\{\{ secrets.SENTRY_AUTH_TOKEN \}\}/);
  assert.match(monitor, /LINEAR_API_KEY: \$\{\{ secrets.LINEAR_API_KEY \}\}/);
  assert.match(monitor, /release-approved-app-store-version.rb/);
  const adapter = read('../../apps/ios/LogYourBody/Services/ErrorTrackingService.swift');
  assert.ok(adapter.includes('options.releaseName = "ios-\\(version) (\\(build))"'));
});
