/** @jest-environment node */

import { generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import { createMcpRouteHandlers } from '@/app/api/mcp/route-handlers';
import { MemoryWeightLifecycle } from '@/lib/metrics/memory-weight-lifecycle';
import { LYB_MCP_SCOPES } from '@/lib/mcp/contract';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { HEALTH_VAULT_WIDGET_URI } from './constants';
import {
  auditTranscript,
  HEALTH_VAULT_SENTINELS,
  HEALTH_VAULT_TRANSCRIPT_FIXTURES,
  sentinelHits,
  type TranscriptTurn,
} from './payload-audit';
import { createHealthVaultService } from './service';
import { MemoryHealthVaultStore } from './session-store';
import type { HealthVaultReader, VaultSnapshot } from './types';

const ISSUER = 'https://jov.ie/api/auth';
const ORIGIN = 'http://localhost:3000';
const RESOURCE = `${ORIGIN}/api/mcp`;
const NOW = new Date('2026-03-01T00:00:00.000Z');
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);
const SCOPES = [
  LYB_MCP_SCOPES.trainingRead,
  LYB_MCP_SCOPES.trainingWrite,
  LYB_MCP_SCOPES.metricsRead,
  LYB_MCP_SCOPES.metricsWrite,
  LYB_MCP_SCOPES.vaultRead,
].join(' ');

const issuerKey = generateKeyPairSync('ed25519');
const publicJwk = { ...issuerKey.publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'EdDSA' };

function seed(): VaultSnapshot {
  return {
    dexa: [
      { id: 'dx1', measuredOn: '2026-01-01', bodyFatPercent: 17.3417, leanMassKg: 60.5 },
      { id: 'dx2', measuredOn: '2026-02-01', bodyFatPercent: 16.2, leanMassKg: 61.25 },
    ],
    photos: [
      {
        id: 'ph_SENTINEL',
        bytes: new TextEncoder().encode('SENTINEL_BYTES_9f3a'),
        contentType: 'image/png',
      },
    ],
    weighIns: [{ id: 'w1', measuredOn: '2026-02-02', weightKg: 81.2229 }],
  };
}

function mint(claims: Record<string, unknown> = {}, key: KeyObject = issuerKey.privateKey) {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const signingInput = `${encode({ alg: 'EdDSA', typ: 'JWT', kid: 'k1' })}.${encode({
    iss: ISSUER,
    aud: RESOURCE,
    sub: 'subject-a',
    azp: 'chatgpt',
    scope: SCOPES,
    iat: NOW_SECONDS,
    exp: NOW_SECONDS + 900,
    ...claims,
  })}`;
  return `${signingInput}.${sign(null, Buffer.from(signingInput), key).toString('base64url')}`;
}

function harness(options: { vault?: boolean; metrics?: boolean; delegated?: boolean } = {}) {
  let reads = 0;
  const reader: HealthVaultReader = {
    async read() {
      reads += 1;
      return seed();
    },
  };
  const store = new MemoryHealthVaultStore();
  const service = createHealthVaultService({ reader, store, now: () => NOW });
  const handlers = createMcpRouteHandlers({
    enabled: () => true,
    issuer: ISSUER,
    canonicalApiOrigin: () => null,
    jwks: { keys: async () => [publicJwk] },
    records: new MemoryTrainingRecords(),
    revisions: undefined,
    delegatedEnabled: () => options.delegated ?? true,
    metricsEnabled: () => options.metrics ?? true,
    vaultEnabled: () => options.vault ?? true,
    vault: service,
    weight: new MemoryWeightLifecycle(),
    reserveRequest: async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }),
    now: () => NOW,
    createId: () => '22222222-2222-4222-8222-222222222222',
  });
  return { handlers, service, store, reads: () => reads };
}

async function post(
  h: ReturnType<typeof harness>,
  method: string,
  params?: unknown,
  claims: Record<string, unknown> = {},
) {
  const response = await h.handlers.post(
    new Request(RESOURCE, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${mint(claims)}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
    }),
  );
  const text = await response.text();
  const headers = [...response.headers.entries()]
    .map(([key, value]) => `${key}: ${value}`)
    .join('\n');
  return { status: response.status, text, headers, body: text ? JSON.parse(text) : null };
}

function expectClean(label: string, value: unknown) {
  const hits = sentinelHits(value);
  expect({ label, hits }).toEqual({ label, hits: [] });
}

describe('health vault payload audit', () => {
  it('keeps seeded measurements out of every JSON-RPC response', async () => {
    expect(JSON.stringify(17.3417)).toBe('17.3417');
    const h = harness();
    const calls: Array<{ label: string; text: string; headers: string }> = [];
    const record = async (
      label: string,
      method: string,
      params?: unknown,
      claims?: Record<string, unknown>,
    ) => {
      const response = await post(h, method, params, claims);
      calls.push({ label, text: response.text, headers: response.headers });
      return response;
    };

    const init = await record('initialize', 'initialize', { protocolVersion: '2025-06-18' });
    expect(init.body.result.capabilities.resources).toEqual({ listChanged: false });
    expect(init.body.result.instructions).toContain('share_summary_with_chatgpt');
    await record('ping', 'ping');
    const listed = await record('tools/list', 'tools/list');
    const names = (listed.body.result.tools as Array<{ name: string }>).map((tool) => tool.name);
    expect(names).toEqual(
      expect.arrayContaining([
        'get_todays_workout',
        'log_sets',
        'create_weight_entry',
        'open_health_vault',
        'share_summary_with_chatgpt',
        'revise_training_program',
      ]),
    );
    await record('resources/list', 'resources/list');
    await record('resources/read', 'resources/read', { uri: HEALTH_VAULT_WIDGET_URI });
    await record('resources/read missing', 'resources/read', {
      uri: 'ui://logyourbody/missing.html',
    });

    for (const name of names) {
      await record(`tools/call ${name}`, 'tools/call', { name, arguments: {} });
    }

    const open = calls.find((call) => call.label === 'tools/call open_health_vault');
    const openBody = JSON.parse(open?.text ?? '{}');
    expect(openBody.result.structuredContent).toEqual({
      vault: 'ready',
      items: { dexa: 2, photos: 1, weigh_ins: 1 },
    });
    expect(openBody.result._meta).toEqual({ viewHandle: expect.stringMatching(/^vh_/) });
    expect(openBody.result.content[0].text).toContain('counts only');
    expect(h.reads()).toBeGreaterThan(0);

    for (const call of calls) {
      expectClean(call.label, call.text);
      expectClean(`${call.label} headers`, call.headers);
    }
    for (const sentinel of HEALTH_VAULT_SENTINELS) {
      expect(calls.some((call) => call.text.includes(sentinel))).toBe(false);
    }
  });

  it('does not echo a sentinel supplied as a tool argument', async () => {
    const h = harness();
    const missing = await post(h, 'tools/call', {
      name: 'share_summary_with_chatgpt',
      arguments: { consentId: '17.34170' },
    });
    const extra = await post(h, 'tools/call', {
      name: 'share_summary_with_chatgpt',
      arguments: { consentId: 'consent-ok', bodyFatPercent: 17.3417 },
    });
    const open = await post(h, 'tools/call', {
      name: 'open_health_vault',
      arguments: { weightKg: 81.2229 },
    });
    expectClean('missing consent', missing.text);
    expectClean('extra field', extra.text);
    expectClean('open extra', open.text);
    expect(missing.body.result.isError).toBe(true);
    expect(extra.body.result.isError).toBe(true);
    expect(open.body.result.isError).toBe(true);
  });

  it('returns a chosen summary only after the widget confirms it', async () => {
    const h = harness();
    const opened = await h.service.open('subject-a');
    if (!opened.ok) throw new Error('open failed');
    const redeemed = await h.service.redeem(opened.handle, ORIGIN);
    if (!redeemed.ok) throw new Error('redeem failed');
    const confirmed = await h.service.confirm({
      confirmToken: redeemed.view.confirmToken,
      fields: ['body_fat'],
    });
    if (!confirmed.ok) throw new Error('confirm failed');

    const shared = await post(h, 'tools/call', {
      name: 'share_summary_with_chatgpt',
      arguments: { consentId: confirmed.consentId },
    });
    expect(shared.body.result.isError).toBeUndefined();
    expect(sentinelHits(shared.text)).toEqual(['17.3417']);
    expect(shared.text).not.toContain('81.2229');
    expect(shared.text).not.toContain('ph_SENTINEL');
    expect(shared.text).not.toContain('SENTINEL_BYTES_9f3a');
    expect(sentinelHits(h.store.events)).toEqual([]);

    const replay = await post(h, 'tools/call', {
      name: 'share_summary_with_chatgpt',
      arguments: { consentId: confirmed.consentId },
    });
    expectClean('replay', replay.text);
  });

  it('hides the vault view from clients without a widget and while the gate is closed', async () => {
    const grok = harness();
    const listed = await post(grok, 'tools/list', {}, { azp: 'grok' });
    const names = (listed.body.result.tools as Array<{ name: string }>).map((tool) => tool.name);
    expect(names).toContain('share_summary_with_chatgpt');
    expect(names).not.toContain('open_health_vault');
    const hidden = await post(
      grok,
      'tools/call',
      { name: 'open_health_vault', arguments: {} },
      { azp: 'grok' },
    );
    expect(hidden.body.result.content[0].text).toBe('Unknown tool.');
    expectClean('grok open', hidden.text);

    const closed = harness({ vault: false, metrics: false, delegated: false });
    const training = await post(closed, 'tools/list');
    expect(
      (training.body.result.tools as Array<{ name: string }>).map((tool) => tool.name),
    ).toEqual([
      'get_todays_workout',
      'log_sets',
      'control_workout',
      'correct_set',
      'log_session_feedback',
      'swap_exercise',
      'get_training_progress',
    ]);
    const before = closed.reads();
    const denied = await post(closed, 'tools/call', { name: 'open_health_vault', arguments: {} });
    expect(denied.body.result.content[0].text).toBe('Unknown tool.');
    expect(closed.reads()).toBe(before);
    const resources = await post(closed, 'resources/list');
    expect(resources.body.result.resources).toEqual([]);
    const init = await post(closed, 'initialize', {});
    expect(init.body.result.capabilities).toEqual({ tools: { listChanged: false } });
  });

  it('audits ten scripted transcripts and rejects an unconfirmed sentinel', () => {
    expect(HEALTH_VAULT_TRANSCRIPT_FIXTURES).toHaveLength(10);
    expect(auditTranscript(HEALTH_VAULT_TRANSCRIPT_FIXTURES.flat())).toEqual([]);
    const confirmed = HEALTH_VAULT_TRANSCRIPT_FIXTURES.flat().filter((turn) => turn.shareConfirmed);
    expect(sentinelHits(confirmed.map((turn) => turn.text).join('\n')).sort()).toEqual([
      '17.3417',
      '81.2229',
    ]);

    const leaked: TranscriptTurn[] = [
      {
        role: 'tool',
        tool: 'share_summary_with_chatgpt',
        shareConfirmed: false,
        text: 'Body fat 17.3417%.',
      },
      { role: 'assistant', text: 'Weight 81.2229 kg.' },
      { role: 'tool', tool: 'open_health_vault', shareConfirmed: true, text: 'ph_SENTINEL' },
    ];
    expect(auditTranscript(leaked)).toEqual(['17.3417', '81.2229', 'ph_SENTINEL']);
  });
});
