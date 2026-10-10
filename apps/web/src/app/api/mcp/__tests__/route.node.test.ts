/** @jest-environment node */

import { generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { storeProgramSetup } from '@/lib/training/service';
import { LYB_MCP_SCOPES } from '@/lib/mcp/contract';
import { createMcpRouteHandlers } from '../route-handlers';

const ISSUER = 'https://jov.ie/api/auth';
const ORIGIN = 'http://localhost:3000';
const RESOURCE = `${ORIGIN}/api/mcp`;
const NOW = new Date('2026-01-10T12:00:00.000Z');
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);
const BOTH_SCOPES = `${LYB_MCP_SCOPES.trainingRead} ${LYB_MCP_SCOPES.trainingWrite}`;

const issuerKey = generateKeyPairSync('ed25519');
const strangerKey = generateKeyPairSync('ed25519');
const publicJwk = { ...issuerKey.publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'EdDSA' };

function mint(claims: Record<string, unknown>, key: KeyObject = issuerKey.privateKey, kid = 'k1') {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const signingInput = `${encode({ alg: 'EdDSA', typ: 'JWT', kid })}.${encode({
    iss: ISSUER,
    aud: RESOURCE,
    sub: 'subject-a',
    azp: 'chatgpt',
    scope: BOTH_SCOPES,
    iat: NOW_SECONDS,
    exp: NOW_SECONDS + 900,
    ...claims,
  })}`;
  return `${signingInput}.${sign(null, Buffer.from(signingInput), key).toString('base64url')}`;
}

function harness(options: { enabled?: boolean; canonical?: string | null } = {}) {
  const records = new MemoryTrainingRecords();
  let nextId = 1;
  const jwksCalls: boolean[] = [];
  const handlers = createMcpRouteHandlers({
    enabled: () => options.enabled ?? true,
    issuer: ISSUER,
    canonicalApiOrigin: () => options.canonical ?? null,
    jwks: {
      keys: async (refresh = false) => {
        jwksCalls.push(refresh);
        return [publicJwk];
      },
    },
    records,
    reserveRequest: async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }),
    now: () => NOW,
    createId: () => `22222222-2222-4222-8222-${String(nextId++).padStart(12, '0')}`,
  });
  return { handlers, records, jwksCalls };
}

function rpc(
  method: string,
  params?: unknown,
  token: string | null = mint({}),
  id: number | null = 1,
) {
  return new Request(`${ORIGIN}/api/mcp`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ jsonrpc: '2.0', ...(id === null ? {} : { id }), method, params }),
  });
}

async function call(
  h: ReturnType<typeof harness>,
  name: string,
  args: unknown = {},
  token?: string,
) {
  const response = await h.handlers.post(
    rpc('tools/call', { name, arguments: args }, token ?? mint({})),
  );
  expect(response.status).toBe(200);
  return (await response.json()).result as {
    content: Array<{ text: string }>;
    structuredContent?: Record<string, any>;
    isError?: boolean;
    _meta?: Record<string, string[]>;
  };
}

async function enroll(h: ReturnType<typeof harness>) {
  await storeProgramSetup({
    records: h.records,
    subject: 'subject-a',
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'dumbbells',
    },
    now: NOW,
    createId: () => '33333333-3333-4333-8333-000000000001',
  });
}

describe('LogYourBody MCP route', () => {
  it('is invisible while disabled', async () => {
    const h = harness({ enabled: false });
    expect((await h.handlers.post(rpc('tools/list'))).status).toBe(404);
    expect(
      h.handlers.metadata(new Request(`${ORIGIN}/.well-known/oauth-protected-resource/api/mcp`))
        .status,
    ).toBe(404);
  });

  it('publishes protected resource metadata that points at the Jovie issuer', async () => {
    const h = harness();
    const response = h.handlers.metadata(
      new Request(`${ORIGIN}/.well-known/oauth-protected-resource/api/mcp`),
    );
    expect(await response.json()).toMatchObject({
      resource: RESOURCE,
      authorization_servers: [ISSUER],
      scopes_supported: [LYB_MCP_SCOPES.trainingRead, LYB_MCP_SCOPES.trainingWrite],
    });
  });

  it('challenges requests without a bearer token', async () => {
    const response = await harness().handlers.post(rpc('initialize', {}, null));
    expect(response.status).toBe(401);
    expect(response.headers.get('www-authenticate')).toBe(
      `Bearer resource_metadata="${ORIGIN}/.well-known/oauth-protected-resource/api/mcp"`,
    );
  });

  it.each([
    ['a foreign signing key', () => mint({}, strangerKey.privateKey)],
    ['another audience', () => mint({ aud: 'https://www.logyourbody.com/api/other' })],
    ['another issuer', () => mint({ iss: 'https://evil.example/api/auth' })],
    ['an expired token', () => mint({ exp: NOW_SECONDS - 120 })],
    ['a token that is not yet valid', () => mint({ nbf: NOW_SECONDS + 600 })],
    ['a missing subject', () => mint({ sub: '' })],
    ['an unsigned token', () => mint({}).split('.').slice(0, 2).join('.') + '.'],
  ])('rejects %s', async (_label, token) => {
    const response = await harness().handlers.post(rpc('tools/list', {}, token()));
    expect(response.status).toBe(401);
    expect(response.headers.get('www-authenticate')).toContain('error="invalid_token"');
  });

  it('rejects an alg other than EdDSA even with a valid-looking body', async () => {
    const [, payload] = mint({}).split('.');
    const header = Buffer.from(JSON.stringify({ alg: 'none', kid: 'k1' })).toString('base64url');
    const response = await harness().handlers.post(rpc('tools/list', {}, `${header}.${payload}.`));
    expect(response.status).toBe(401);
  });

  it('refetches the JWKS once for an unknown key id', async () => {
    const h = harness();
    const response = await h.handlers.post(
      rpc('tools/list', {}, mint({}, issuerKey.privateKey, 'rotated')),
    );
    expect(response.status).toBe(401);
    expect(h.jwksCalls).toEqual([false, true]);
  });

  it('pins the audience to the canonical API host in production', async () => {
    const h = harness({ canonical: 'https://www.logyourbody.com' });
    expect((await h.handlers.post(rpc('tools/list'))).status).toBe(401);
    const pinned = mint({ aud: 'https://www.logyourbody.com/api/mcp' });
    expect((await h.handlers.post(rpc('tools/list', {}, pinned))).status).toBe(200);
  });

  it('negotiates the protocol and lists annotated tools', async () => {
    const h = harness();
    const init = await (
      await h.handlers.post(rpc('initialize', { protocolVersion: '2025-06-18' }))
    ).json();
    expect(init.result).toMatchObject({
      protocolVersion: '2025-06-18',
      serverInfo: { name: 'logyourbody' },
    });

    const notified = await h.handlers.post(
      rpc('notifications/initialized', undefined, mint({}), null),
    );
    expect(notified.status).toBe(202);

    const { result } = await (await h.handlers.post(rpc('tools/list'))).json();
    const byName = Object.fromEntries(result.tools.map((tool: any) => [tool.name, tool]));
    expect(Object.keys(byName)).toEqual([
      'get_todays_workout',
      'log_sets',
      'log_session_feedback',
      'get_training_progress',
    ]);
    for (const tool of result.tools) {
      expect(tool.annotations).toMatchObject({ destructiveHint: false, openWorldHint: false });
      expect(typeof tool.annotations.readOnlyHint).toBe('boolean');
    }
    expect(byName.get_todays_workout.annotations.readOnlyHint).toBe(true);
    expect(byName.log_sets.annotations.readOnlyHint).toBe(false);
    expect(byName.log_sets.securitySchemes).toEqual([
      { type: 'oauth2', scopes: [LYB_MCP_SCOPES.trainingWrite] },
    ]);
  });

  it('asks for the write scope when a read-only grant tries to log', async () => {
    const h = harness();
    await enroll(h);
    const result = await call(
      h,
      'log_sets',
      { exercise: 'goblet squat', sets: [{ reps: 8, rir: 3 }] },
      mint({ scope: LYB_MCP_SCOPES.trainingRead }),
    );
    expect(result.isError).toBe(true);
    expect(result._meta?.['mcp/www_authenticate']?.[0]).toContain(
      `error="insufficient_scope", scope="${LYB_MCP_SCOPES.trainingWrite}"`,
    );
  });

  it('sends unenrolled users to the iPhone app instead of enrolling them', async () => {
    const result = await call(harness(), 'get_todays_workout');
    expect(result.structuredContent).toEqual({ status: 'not_enrolled' });
    expect(result.content[0]?.text).toContain('LogYourBody iPhone app');
  });

  it('does not start a session when the exercise is not in the plan', async () => {
    const h = harness();
    await enroll(h);
    const result = await call(h, 'log_sets', {
      exercise: 'barbell back squat',
      sets: [{ reps: 8, rir: 2 }],
    });
    expect(result.isError).toBe(true);
    expect(result.content[0]?.text).toContain("Today's exercises: Goblet squat");
    expect(await h.records.pull('subject-a', 'training_sessions')).toMatchObject({ records: [] });
  });

  it('previews, logs by voice-style input, and reports progress', async () => {
    const h = harness();
    await enroll(h);

    const preview = await call(h, 'get_todays_workout');
    expect(preview.structuredContent).toMatchObject({ status: 'workout', week: 1, weekCount: 4 });
    expect(preview.structuredContent?.session.exercises[0]).toMatchObject({
      name: 'Goblet squat',
      sets: 2,
      targetReps: 8,
      targetRir: 4,
    });
    expect(await h.records.pull('subject-a', 'training_sessions')).toMatchObject({ records: [] });

    const logged = await call(h, 'log_sets', {
      exercise: 'Goblet Squat',
      weightUnit: 'lb',
      sets: [
        { reps: 10, rir: 3, load: 50 },
        { reps: 9, rir: 2, load: 50 },
        { reps: 8, rir: 1, load: 50 },
      ],
    });
    expect(logged.isError).toBeUndefined();
    expect(logged.structuredContent).toMatchObject({
      exercise: { id: 'goblet_squat', plannedSets: 2 },
      logged: [
        { setNumber: 1, reps: 10, loadKg: 22.68, loadLb: 50, rir: 3 },
        { setNumber: 2, reps: 9, loadKg: 22.68, loadLb: 50, rir: 2 },
      ],
      skipped: [{ setNumber: null, reason: "today's plan has 2 sets" }],
    });

    const again = await call(h, 'log_sets', {
      exercise: 'goblet_squat',
      sets: [{ reps: 10, rir: 3, setNumber: 1 }],
    });
    expect(again.isError).toBe(true);
    expect(again.structuredContent?.skipped).toEqual([{ setNumber: 1, reason: 'already logged' }]);

    const ambiguous = await call(h, 'log_sets', {
      exercise: 'dumbbell',
      sets: [{ reps: 10, rir: 3 }],
    });
    expect(ambiguous.isError).toBe(true);
    expect(ambiguous.content[0]?.text).toContain('more than one exercise');

    const progress = await call(h, 'get_training_progress', { exercise: 'goblet' });
    expect(progress.structuredContent).toMatchObject({
      enrolled: true,
      setsLast7Days: 2,
      exercises: [
        {
          exerciseId: 'goblet_squat',
          name: 'Goblet squat',
          totalSets: 2,
          heaviestSet: { loadKg: 22.68, reps: 10 },
        },
      ],
    });

    const checkIn = await call(h, 'log_session_feedback', {
      soreness: 3,
      pump: 6,
      performance: 'stable',
      jointPain: 5,
    });
    expect(checkIn.isError).toBeUndefined();
    expect(checkIn.content[0]?.text).toContain('qualified clinician');
  });

  it('keeps previewed targets after logging an exercise and honors a later pain stop', async () => {
    const h = harness();
    await enroll(h);
    const original = (await call(h, 'get_todays_workout')).structuredContent;
    expect(
      (
        await call(h, 'log_sets', {
          exercise: 'goblet_squat',
          sets: [
            { reps: 10, load: 25, rir: 4 },
            { reps: 10, load: 25, rir: 4 },
          ],
        })
      ).isError,
    ).toBeUndefined();
    const rowsBefore = await h.records.listAll('subject-a');
    const reopened = (await call(h, 'get_todays_workout')).structuredContent;
    expect(reopened?.session.id).toBe(original?.session.id);
    expect(reopened?.session.exercises).toEqual(
      original?.session.exercises.map((exercise: Record<string, unknown>) => ({
        ...exercise,
        loggedSets:
          exercise.id === 'goblet_squat'
            ? [
                { setNumber: 1, reps: 10, loadKg: 25, loadLb: 55.1, rir: 4 },
                { setNumber: 2, reps: 10, loadKg: 25, loadLb: 55.1, rir: 4 },
              ]
            : [],
      })),
    );
    expect(await h.records.listAll('subject-a')).toEqual(rowsBefore);
    await call(h, 'log_session_feedback', {
      soreness: 2,
      pump: 5,
      performance: 'stable',
      jointPain: 5,
    });
    expect((await call(h, 'get_todays_workout')).structuredContent?.session).toMatchObject({
      safetyStop: true,
      exercises: [],
    });
    expect(
      (
        await call(h, 'log_sets', {
          exercise: 'dumbbell bench press',
          sets: [{ reps: 10, rir: 4 }],
        })
      ).isError,
    ).toBe(true);
    expect((await h.records.pull('subject-a', 'logged_sets')).records).toHaveLength(2);
  });

  it('validates tool input before touching records', async () => {
    const h = harness();
    const result = await call(h, 'log_sets', { exercise: 'x', sets: [{ reps: 0, rir: 9 }] });
    expect(result.isError).toBe(true);
    expect(result.content[0]?.text).toBe('Invalid input: sets.0.reps, sets.0.rir.');
  });
});
