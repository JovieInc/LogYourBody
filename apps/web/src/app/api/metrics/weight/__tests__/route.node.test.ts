/** @jest-environment node */

import { generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { LYB_MCP_SCOPES } from '@/lib/mcp/contract';
import { verifyAccessToken } from '@/lib/mcp/access-token';
import { MemoryWeightLifecycle, grantedSubject } from '@/lib/metrics/memory-weight-lifecycle';
import { createMcpRouteHandlers } from '@/app/api/mcp/route-handlers';
import { createWeightRouteHandlers } from '../route-handlers';

const ISSUER = 'https://jov.ie/api/auth';
const ORIGIN = 'http://localhost:3000';
const RESOURCE = `${ORIGIN}/api/mcp`;
const NOW = new Date('2026-10-13T15:00:00.000Z');
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);
const SUBJECT = 'subject-a';
const RECORD = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const OP = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const SCOPES = `${LYB_MCP_SCOPES.metricsRead} ${LYB_MCP_SCOPES.metricsWrite}`;

const issuerKey = generateKeyPairSync('ed25519');
const publicJwk = { ...issuerKey.publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'EdDSA' };

function mint(claims: Record<string, unknown> = {}, key: KeyObject = issuerKey.privateKey) {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const signingInput = `${encode({ alg: 'EdDSA', typ: 'JWT', kid: 'k1' })}.${encode({
    iss: ISSUER,
    aud: RESOURCE,
    sub: SUBJECT,
    azp: 'chatgpt',
    scope: SCOPES,
    iat: NOW_SECONDS,
    exp: NOW_SECONDS + 900,
    ...claims,
  })}`;
  return `${signingInput}.${sign(null, Buffer.from(signingInput), key).toString('base64url')}`;
}

function body(overrides: Record<string, unknown> = {}) {
  return {
    operation_id: OP,
    record_id: RECORD,
    value: 180,
    unit: 'lb',
    measured_at: '2026-10-13T08:00:00-07:00',
    utc_offset_minutes: -420,
    local_date: '2026-10-13',
    iana_zone: 'America/Los_Angeles',
    ...overrides,
  };
}

function harness(options: { enabled?: boolean; scopes?: ReadonlySet<string> | null } = {}) {
  const store = new MemoryWeightLifecycle();
  store.setGrant(grantedSubject(SUBJECT));
  let authentications = 0;
  const handlers = createWeightRouteHandlers({
    enabled: () => options.enabled ?? true,
    authenticate: async () => {
      authentications += 1;
      if (options.scopes === null) return null;
      return {
        subject: SUBJECT,
        scopes:
          options.scopes ?? new Set([LYB_MCP_SCOPES.metricsRead, LYB_MCP_SCOPES.metricsWrite]),
      };
    },
    store,
    now: () => NOW,
  });
  return { handlers, store, authentications: () => authentications };
}

async function post(
  handlers: ReturnType<typeof harness>['handlers'],
  path: 'post' | 'correct' | 'remove',
  payload: unknown,
) {
  const response = await handlers[path](
    new Request(`${ORIGIN}/api/metrics/weight`, {
      method: 'POST',
      headers: { authorization: 'Bearer test', 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    }),
  );
  return { status: response.status, body: await response.json().catch(() => null) };
}

describe('weight HTTP lifecycle', () => {
  it('creates, reads, corrects the same id, deletes, and reads the tombstone', async () => {
    const { handlers, store } = harness();
    const created = await post(handlers, 'post', body());
    expect(created.status).toBe(200);
    expect(created.body.receipt.record).toMatchObject({
      id: RECORD,
      revision: 1,
      weight_kg: '81.646627',
    });
    expect(created.body.receipt.device).toEqual({ healthkit: 'not_claimed' });

    const listed = await handlers.get(
      new Request(`${ORIGIN}/api/metrics/weight`, { headers: { authorization: 'Bearer test' } }),
    );
    expect(listed.status).toBe(200);
    expect(await listed.json()).toMatchObject({ records: [{ id: RECORD, revision: 1 }] });

    const corrected = await post(
      handlers,
      'correct',
      body({
        operation_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        value: 82.5,
        unit: 'kg',
        expected_revision: 1,
      }),
    );
    expect(corrected.status).toBe(200);
    expect(corrected.body.receipt.record).toMatchObject({
      id: RECORD,
      revision: 2,
      weight_kg: '82.500000',
    });
    expect(store.entries.size).toBe(1);

    const removed = await post(handlers, 'remove', {
      operation_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      record_id: RECORD,
      expected_revision: 2,
    });
    expect(removed.status).toBe(200);
    expect(removed.body.receipt.record.deleted_at).toBe(NOW.toISOString());

    const live = await handlers.get(
      new Request(`${ORIGIN}/api/metrics/weight`, { headers: { authorization: 'Bearer test' } }),
    );
    expect(await live.json()).toMatchObject({ records: [] });
    const tombstone = await handlers.get(
      new Request(`${ORIGIN}/api/metrics/weight?record_id=${RECORD}`, {
        headers: { authorization: 'Bearer test' },
      }),
    );
    expect(await tombstone.json()).toMatchObject({
      records: [{ id: RECORD, deleted_at: NOW.toISOString() }],
    });
  });

  it('rejects the wrong caller, a training scope, a closed gate, and a bad token without writing', async () => {
    const closed = harness({ enabled: false });
    const hidden = await closed.handlers.post(
      new Request(`${ORIGIN}/api/metrics/weight`, { method: 'POST', body: '{}' }),
    );
    expect(hidden.status).toBe(404);
    expect(closed.authentications()).toBe(0);
    expect(closed.store.mutations).toBe(0);

    const training = harness({ scopes: new Set([LYB_MCP_SCOPES.trainingWrite]) });
    const denied = await post(training.handlers, 'post', body());
    expect(denied.status).toBe(403);
    expect(denied.body).toEqual({ error: 'insufficient_scope' });
    expect(training.store.mutations).toBe(0);

    const anon = harness({ scopes: null });
    const unsigned = await post(anon.handlers, 'post', body());
    expect(unsigned.status).toBe(401);
    expect(anon.store.mutations).toBe(0);

    const owned = harness();
    const spoofed = await post(owned.handlers, 'post', body({ subject: 'subject-b' }));
    expect(spoofed.status).toBe(403);
    expect(spoofed.body).toEqual({ error: 'spoofed_subject' });
    expect(owned.store.mutations).toBe(0);
  });

  it('rejects a wrong audience and an expired token before any store call', async () => {
    const store = new MemoryWeightLifecycle();
    store.setGrant(grantedSubject(SUBJECT));
    const handlers = createWeightRouteHandlers({
      enabled: () => true,
      authenticate: async (request) => {
        const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
        const principal = await verifyAccessToken(token, {
          issuer: ISSUER,
          audience: RESOURCE,
          jwks: { keys: async () => [publicJwk] },
          nowSeconds: NOW_SECONDS,
        });
        return principal ? { subject: principal.subject, scopes: principal.scopes } : null;
      },
      store,
      now: () => NOW,
    });
    const wrongAudience = await handlers.post(
      new Request(`${ORIGIN}/api/metrics/weight`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${mint({ aud: 'https://www.logyourbody.com/api/other' })}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify(body()),
      }),
    );
    const expired = await handlers.post(
      new Request(`${ORIGIN}/api/metrics/weight`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${mint({ exp: NOW_SECONDS - 120 })}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify(body()),
      }),
    );
    expect(wrongAudience.status).toBe(401);
    expect(expired.status).toBe(401);
    expect(store.mutations).toBe(0);
  });
});

describe('weight MCP lifecycle', () => {
  function mcp(metricsEnabled: boolean) {
    const weight = new MemoryWeightLifecycle();
    weight.setGrant(grantedSubject(SUBJECT));
    const handlers = createMcpRouteHandlers({
      enabled: () => true,
      metricsEnabled: () => metricsEnabled,
      issuer: ISSUER,
      canonicalApiOrigin: () => null,
      jwks: { keys: async () => [publicJwk] },
      records: new MemoryTrainingRecords(),
      weight,
      reserveRequest: async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }),
      now: () => NOW,
      createId: () => '22222222-2222-4222-8222-222222222222',
    });
    return { handlers, weight };
  }

  async function call(
    handlers: ReturnType<typeof mcp>['handlers'],
    name: string,
    args: unknown,
    scope = SCOPES,
  ) {
    const response = await handlers.post(
      new Request(`${ORIGIN}/api/mcp`, {
        method: 'POST',
        headers: { authorization: `Bearer ${mint({ scope })}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: 1,
          method: 'tools/call',
          params: { name, arguments: args },
        }),
      }),
    );
    const payload = await response.json();
    return payload.result as {
      isError?: boolean;
      structuredContent?: Record<string, unknown>;
      _meta?: Record<string, string[]>;
    };
  }

  it('hides the tools until the gate is on, then runs the same lifecycle', async () => {
    const off = mcp(false);
    const listedOff = await off.handlers.post(
      new Request(`${ORIGIN}/api/mcp`, {
        method: 'POST',
        headers: { authorization: `Bearer ${mint()}`, 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
      }),
    );
    const namesOff = ((await listedOff.json()).result.tools as Array<{ name: string }>).map(
      (tool) => tool.name,
    );
    expect(namesOff).not.toContain('create_weight_entry');
    const hidden = await call(off.handlers, 'create_weight_entry', body());
    expect(hidden.isError).toBe(true);
    expect(off.weight.mutations).toBe(0);

    const on = mcp(true);
    const listedOn = await on.handlers.post(
      new Request(`${ORIGIN}/api/mcp`, {
        method: 'POST',
        headers: { authorization: `Bearer ${mint()}`, 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
      }),
    );
    const tools = (await listedOn.json()).result.tools as Array<{
      name: string;
      annotations: { destructiveHint: boolean };
    }>;
    expect(tools.map((tool) => tool.name)).toEqual(
      expect.arrayContaining([
        'create_weight_entry',
        'list_weight_entries',
        'correct_weight_entry',
        'delete_weight_entry',
      ]),
    );
    expect(
      tools.find((tool) => tool.name === 'delete_weight_entry')?.annotations.destructiveHint,
    ).toBe(true);
    expect(tools.find((tool) => tool.name === 'log_sets')?.annotations.destructiveHint).toBe(false);

    const metadata = await on.handlers.metadata(
      new Request(`${ORIGIN}/.well-known/oauth-protected-resource/api/mcp`),
    );
    expect(await metadata.json()).toMatchObject({
      scopes_supported: expect.arrayContaining([
        LYB_MCP_SCOPES.metricsRead,
        LYB_MCP_SCOPES.metricsWrite,
      ]),
    });

    const training = await call(
      on.handlers,
      'create_weight_entry',
      body(),
      LYB_MCP_SCOPES.trainingWrite,
    );
    expect(training.isError).toBe(true);
    expect(training._meta?.['mcp/www_authenticate']?.[0]).toContain('insufficient_scope');
    expect(on.weight.mutations).toBe(0);

    const created = await call(on.handlers, 'create_weight_entry', body());
    expect(created.isError).toBeUndefined();
    expect(created.structuredContent?.receipt).toMatchObject({
      record: { id: RECORD, revision: 1 },
      device: { healthkit: 'not_claimed' },
    });
    const corrected = await call(
      on.handlers,
      'correct_weight_entry',
      body({
        operation_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        value: 82.5,
        unit: 'kg',
        expected_revision: 1,
      }),
    );
    expect(corrected.structuredContent?.receipt).toMatchObject({
      record: { id: RECORD, revision: 2 },
    });
    const removed = await call(on.handlers, 'delete_weight_entry', {
      operation_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      record_id: RECORD,
      expected_revision: 2,
    });
    expect(removed.structuredContent?.receipt).toMatchObject({
      record: { revision: 3, deleted_at: NOW.toISOString() },
    });
    const read = await call(
      on.handlers,
      'list_weight_entries',
      { record_id: RECORD },
      LYB_MCP_SCOPES.metricsRead,
    );
    expect(read.structuredContent?.records).toMatchObject([
      { id: RECORD, deleted_at: NOW.toISOString() },
    ]);
    expect(on.weight.entries.size).toBe(1);
  });
});
