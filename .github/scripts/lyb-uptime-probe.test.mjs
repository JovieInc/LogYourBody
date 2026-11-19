import assert from 'node:assert/strict';
import { test } from 'node:test';
import { liveProbeEnabled, probeHomepages, runUptimeProbe } from './lyb-uptime-probe.mjs';

const www = 'https://www.logyourbody.com/';
const apex = 'https://logyourbody.com/';
const webhook = 'https://slack.example.com/fixture';
const linear = 'https://api.linear.app/graphql';
const teamId = 'fixture-lyb';
const fixtureTime = Date.parse('2026-11-19T20:14:00Z');
const redirect = (status, location) => ({ status, headers: { location } });
const healthy = { [www]: { status: 200 }, [apex]: redirect(308, www) };

function createFixture(overrides = {}) {
  const responses = { ...healthy, ...overrides };
  const issues = new Map();
  const requests = [];
  const writes = [];
  const messages = [];
  let slackResponse = () => new Response('ok');
  let minute = 0;

  async function fetchImpl(url, options) {
    requests.push(url);
    if (Object.hasOwn(responses, url)) {
      assert.equal(options.method, 'GET');
      assert.equal(options.redirect, 'manual');
      assert.equal(options.cache, 'no-store');
      if (!responses[url]) throw new Error('fixture timeout');
      return new Response(null, responses[url]);
    }
    if (url === webhook) {
      assert.equal(options.method, 'POST');
      assert.equal(options.redirect, 'error');
      messages.push(JSON.parse(options.body));
      return slackResponse();
    }
    assert.equal(url, linear, 'the fixture handles every request in memory');
    assert.equal(options.method, 'POST');
    assert.equal(options.headers.Authorization, 'fixture-linear-key');
    const { query, variables } = JSON.parse(options.body);
    const { id, input } = variables;
    const response = (data) => Response.json({ data });
    if (query.includes('FindUptimeIncidents')) {
      assert.equal(variables.teamKey, 'LYB');
      assert.equal(new Set(variables.ids).size, 12);
      return response({
        teams: {
          nodes: [
            {
              id: teamId,
              states: {
                nodes: [
                  { id: 'todo', type: 'unstarted' },
                  { id: 'done', type: 'completed' },
                ],
              },
            },
          ],
        },
        issues: { nodes: variables.ids.map((key) => issues.get(key)).filter(Boolean) },
      });
    }
    if (query.includes('CreateUptimeIncident')) {
      assert.equal(input.teamId, teamId);
      assert.equal(input.stateId, 'todo');
      assert.match(
        input.id,
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
      assert.ok(!issues.has(input.id), 'duplicate Linear issue ID');
      const identifier = `LYB-fixture-${issues.size + 1}`;
      const issue = {
        ...input,
        identifier,
        url: `https://linear.example.com/issue/${identifier}`,
        team: { id: teamId },
      };
      issues.set(issue.id, issue);
      writes.push({ action: 'create', id: issue.id });
      return response({ issueCreate: { success: true, issue } });
    }
    assert.match(query, /UpdateUptimeIncident/);
    assert.ok(issues.has(id), 'update points to the original Linear issue');
    const issue = { ...issues.get(id), ...input };
    issues.set(id, issue);
    writes.push({ action: 'update', id, ...input });
    return response({ issueUpdate: { success: true, issue } });
  }

  return {
    responses,
    requests,
    issues,
    writes,
    messages,
    fetchImpl,
    setSlackResponse(response) {
      slackResponse = response;
    },
    run(options = {}) {
      return runUptimeProbe({
        apiKey: 'fixture-linear-key',
        webhook,
        fetchImpl,
        now: new Date(fixtureTime + minute++ * 60_000),
        ...options,
      });
    },
  };
}

test('healthy contract checks only www and apex, with no external state changes', async () => {
  const fixture = createFixture({ [apex]: redirect(301, www) });
  const result = await fixture.run();
  assert.deepEqual(
    result.signals.map(({ kind }) => kind),
    [null, null],
  );
  assert.deepEqual(result.results, []);
  assert.deepEqual(result.errors, []);
  assert.deepEqual(fixture.requests, [www, apex, linear]);
  assert.equal(fixture.writes.length, 0);
  assert.equal(fixture.messages.length, 0);
});

for (const [name, host, response, kind] of [
  [
    'paused www 503',
    www,
    { status: 503, headers: { 'X-Vercel-Error': 'DEPLOYMENT_PAUSED' } },
    'deployment-paused',
  ],
  ['apex 308 self-loop', apex, redirect(308, apex), 'redirect-loop'],
]) {
  test(`${name} drill files and pages once, repeats cleanly, and recovers the same issue`, async (t) => {
    const fixture = createFixture({ [host]: response });
    const first = await fixture.run();
    const [incident] = first.results;
    assert.equal(first.results.length, 1);
    assert.equal(incident.hostname, new URL(host).hostname);
    assert.equal(incident.kind, kind);
    assert.equal(incident.action, 'alerted');
    assert.deepEqual(first.errors, []);
    assert.equal(fixture.messages.length, 1);
    assert.ok(fixture.messages[0].text.includes(incident.issue));
    assert.equal(fixture.issues.size, 1);
    const [create] = fixture.writes;
    assert.equal(create.action, 'create');
    assert.equal(create.id, incident.id);

    const writesAtFailure = fixture.writes.length;
    const repeated = await fixture.run();
    assert.deepEqual(repeated.results, [{ ...incident, action: 'already-alerted' }]);
    assert.equal(fixture.writes.length, writesAtFailure);
    assert.equal(fixture.messages.length, 1);

    fixture.responses[host] = healthy[host];
    const recovery = await fixture.run();
    assert.deepEqual(
      recovery.signals.map(({ kind }) => kind),
      [null, null],
    );
    assert.deepEqual(recovery.errors, []);
    assert.deepEqual(recovery.results, [{ ...incident, action: 'recovered' }]);
    assert.equal(fixture.issues.get(incident.id).stateId, 'done');
    assert.match(fixture.issues.get(incident.id).description, /Recovered at .*PST/);
    assert.equal(fixture.writes.length, writesAtFailure + 1);
    assert.equal(fixture.messages.length, 1);
    assert.deepEqual((await fixture.run()).results, []);
    assert.equal(fixture.writes.length, writesAtFailure + 1);

    t.diagnostic(
      `${first.checkedAt} — ${incident.issue} upserted in the first fixture check, 1 mock Slack message`,
    );
    t.diagnostic(`${repeated.checkedAt} — same ${incident.issue}, 0 additional writes or messages`);
    t.diagnostic(`${recovery.checkedAt} — both hosts healthy, same ${incident.issue} marked Done`);
  });
}

test('replayed production events and dead-man ticks leave one issue and one Slack message per key', async () => {
  const fixture = createFixture({ [www]: { status: 503 }, [apex]: redirect(308, apex) });
  const first = await fixture.run();
  assert.deepEqual(
    first.results.map(({ kind }) => kind),
    ['http-503', 'redirect-loop'],
  );
  const writes = fixture.writes.length;
  for (let index = 0; index < 25; index += 1) {
    const replay = await fixture.run();
    assert.deepEqual(
      replay.results,
      first.results.map((item) => ({ ...item, action: 'already-alerted' })),
    );
  }
  assert.equal(fixture.issues.size, 2);
  assert.equal(fixture.messages.length, 2);
  assert.equal(fixture.writes.length, writes);

  fixture.responses[www] = healthy[www];
  const recovered = await fixture.run();
  assert.deepEqual(
    recovered.results.map(({ action }) => action),
    ['recovered', 'already-alerted'],
  );
  fixture.responses[www] = { status: 503 };
  const recurrence = await fixture.run();
  assert.deepEqual(recurrence.results[0], first.results[0]);
  assert.equal(fixture.issues.get(first.results[0].id).stateId, 'todo');
  assert.equal(fixture.issues.size, 2);
  assert.equal(fixture.messages.length, 3);
});

test('rejects unsafe redirect targets, extra hops, and invalid statuses without following them', async () => {
  for (const [responses, expected] of [
    [
      { [apex]: redirect(308, 'https://www.logyourbody.com.example.com/') },
      [null, 'redirect-contract'],
    ],
    [{ [apex]: redirect(308, 'https://www.logyourbody.com/other') }, [null, 'redirect-contract']],
    [{ [apex]: redirect(308, 'https://user@www.logyourbody.com/') }, [null, 'redirect-contract']],
    [{ [apex]: redirect(308, 'http://www.logyourbody.com/') }, [null, 'redirect-contract']],
    [{ [apex]: redirect(308, '/') }, [null, 'redirect-loop']],
    [{ [apex]: redirect(307, www) }, [null, 'redirect-contract']],
    [{ [apex]: { status: 308 } }, [null, 'redirect-contract']],
    [{ [apex]: { status: 200 } }, [null, 'redirect-contract']],
    [{ [www]: redirect(302, apex) }, ['redirect-loop', null]],
    [{ [www]: redirect(308, 'https://another.example.com/') }, ['http-status', null]],
    [{ [www]: { status: 204 } }, ['http-status', null]],
    [
      { [www]: { status: 200, headers: { 'x-vercel-error': 'deployment_paused' } } },
      ['deployment-paused', null],
    ],
    [{ [www]: null }, ['transport', null]],
  ]) {
    const fixture = createFixture(responses);
    const signals = await probeHomepages(fixture.fetchImpl);
    assert.deepEqual(
      signals.map(({ kind }) => kind),
      expected,
    );
    assert.deepEqual(fixture.requests, [www, apex]);
  }
});

test('a known Slack rejection retries on the same issue', async () => {
  const fixture = createFixture({ [www]: { status: 503 } });
  fixture.setSlackResponse(() => new Response('fixture rejection', { status: 429 }));
  const failed = await fixture.run();
  assert.equal(failed.errors[0].reason, 'uptime_slack_rejected_429');
  fixture.setSlackResponse(() => new Response('ok'));
  assert.equal((await fixture.run()).results[0].action, 'alerted');
  assert.equal((await fixture.run()).results[0].action, 'already-alerted');
  assert.equal(fixture.issues.size, 1);
  assert.equal(fixture.messages.length, 2);
});

test('an ambiguous Slack response is visible and is not sent again on replay', async () => {
  const fixture = createFixture({ [www]: { status: 503 } });
  fixture.setSlackResponse(() => {
    throw new Error('fixture timeout with credential-shaped text');
  });
  assert.equal((await fixture.run()).errors[0].reason, 'uptime_slack_delivery_uncertain');
  assert.equal((await fixture.run()).errors[0].reason, 'uptime_slack_delivery_uncertain');
  assert.equal(fixture.issues.size, 1);
  assert.equal(fixture.messages.length, 1);
  fixture.responses[www] = healthy[www];
  assert.equal(
    (await fixture.run()).errors[0].reason,
    'uptime_recovered_without_confirmed_slack_sending',
  );
  assert.equal([...fixture.issues.values()][0].stateId, 'done');
});

test('live CLI gate requires the enabled Symphony workflow on main', () => {
  const env = {
    GITHUB_ACTIONS: 'true',
    GITHUB_WORKFLOW_REF:
      'JovieInc/LogYourBody/.github/workflows/lyb-386-uptime-probe.yml@refs/heads/main',
    LYB_UPTIME_PROBE_ENABLED: 'true',
  };
  assert.equal(liveProbeEnabled(env), true);
  assert.equal(liveProbeEnabled({ ...env, GITHUB_ACTIONS: '' }), false);
  assert.equal(
    liveProbeEnabled({
      ...env,
      GITHUB_WORKFLOW_REF: env.GITHUB_WORKFLOW_REF.replace('main', 'fixture'),
    }),
    false,
  );
  assert.equal(liveProbeEnabled({ ...env, LYB_UPTIME_PROBE_ENABLED: '' }), false);
});
