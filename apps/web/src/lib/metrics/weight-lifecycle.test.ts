import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { delegatedMetricsEnabled, METRICS_AGENT_WEIGHT_GATE } from '@/lib/flags/delegated-metrics';
import { MemoryWeightLifecycle, grantedSubject } from './memory-weight-lifecycle';
import {
  POUNDS_TO_KILOGRAMS,
  correctWeightEntry,
  createWeightEntry,
  decideNativePush,
  deleteWeightEntry,
  listWeightEntries,
  resolveMeasurement,
  resolveWeight,
  type NativePushExisting,
  type WeightLifecyclePort,
} from './weight-lifecycle';

const SUBJECT = 'subject-a';
const OTHER = 'subject-b';
const RECORD = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const RECORD_2 = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const OP = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const OP_2 = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const OP_3 = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const NOW = new Date('2026-10-13T15:00:00.000Z');
const LATER = new Date('2026-10-13T16:00:00.000Z');

const fixtures = JSON.parse(
  readFileSync(join(__dirname, 'weight-lifecycle-fixtures.json'), 'utf8'),
) as {
  pounds_to_kilograms: string;
  cases: Array<{ name: string; value: number; unit: 'kg' | 'lb'; weight_kg: string }>;
  measurements: Array<{
    name: string;
    measured_at: string;
    utc_offset_minutes: number;
    local_date: string;
    iana_zone: string;
  }>;
};

function measurement(overrides: Record<string, unknown> = {}) {
  return {
    measured_at: '2026-10-13T08:00:00-07:00',
    utc_offset_minutes: -420,
    local_date: '2026-10-13',
    iana_zone: 'America/Los_Angeles',
    ...overrides,
  };
}

function createBody(overrides: Record<string, unknown> = {}) {
  return {
    operation_id: OP,
    record_id: RECORD,
    value: 180,
    unit: 'lb',
    ...measurement(),
    ...overrides,
  };
}

function opened(subject = SUBJECT) {
  const store = new MemoryWeightLifecycle();
  store.setGrant(grantedSubject(subject));
  return store;
}

function act(
  store: WeightLifecyclePort,
  body: unknown = createBody(),
  now = NOW,
  subject = SUBJECT,
) {
  return createWeightEntry({ gateEnabled: true, subject, body, store, now });
}

describe('weight lifecycle', () => {
  it('converts explicit kg and lb without guessing', () => {
    expect(POUNDS_TO_KILOGRAMS).toBe(fixtures.pounds_to_kilograms);
    expect(METRICS_AGENT_WEIGHT_GATE).toBe('metrics_agent_weight_lifecycle');
    for (const entry of fixtures.cases) {
      const resolved = resolveWeight(entry.value, entry.unit);
      expect(resolved.ok).toBe(true);
      if (resolved.ok) {
        expect(resolved.weight_kg).toBe(entry.weight_kg);
        expect(resolved.provenance.constant).toBe(fixtures.pounds_to_kilograms);
        expect(resolved.provenance.actor).toBe('agent');
      }
    }
    expect(resolveWeight(32, 'kg')).toMatchObject({ ok: true, weight_kg: '32.000000' });
    expect(resolveWeight(300, 'kg')).toMatchObject({ ok: true, weight_kg: '300.000000' });
    expect(resolveWeight(70, 'lb')).toMatchObject({ ok: true });
    expect(resolveWeight(660, 'lb')).toMatchObject({ ok: true });
    expect(resolveWeight(31.999, 'kg')).toMatchObject({ reason: 'out_of_range' });
    expect(resolveWeight(300.001, 'kg')).toMatchObject({ reason: 'out_of_range' });
    expect(resolveWeight(69.999, 'lb')).toMatchObject({ reason: 'out_of_range' });
    expect(resolveWeight(660.001, 'lb')).toMatchObject({ reason: 'out_of_range' });
    expect(resolveWeight(180.0001, 'lb')).toMatchObject({ reason: 'ambiguous_weight' });
    expect(resolveWeight(Number.NaN, 'kg')).toMatchObject({ reason: 'ambiguous_weight' });
  });

  it('accepts a consistent offset, zone, and local date, including midnight and both DST folds', () => {
    for (const entry of fixtures.measurements) {
      expect(resolveMeasurement(entry)).toMatchObject({ ok: true, measured_at: entry.measured_at });
    }
    const yesterday = measurement({
      measured_at: '2026-10-12T23:30:00-07:00',
      local_date: '2026-10-12',
    });
    expect(resolveMeasurement(yesterday).ok).toBe(true);
    expect(resolveMeasurement(measurement({ measured_at: '2026-10-13T08:00:00' }))).toMatchObject({
      reason: 'ambiguous_timestamp',
    });
    expect(
      resolveMeasurement(measurement({ measured_at: '2026-10-13T24:00:00-07:00' })),
    ).toMatchObject({
      reason: 'ambiguous_timestamp',
    });
    expect(
      resolveMeasurement(measurement({ measured_at: '2026-02-31T00:00:00-08:00' })),
    ).toMatchObject({
      reason: 'ambiguous_timestamp',
    });
    expect(resolveMeasurement(measurement({ utc_offset_minutes: -480 }))).toMatchObject({
      reason: 'offset_mismatch',
    });
    expect(
      resolveMeasurement(
        measurement({
          measured_at: '2026-03-08T00:00:00-07:00',
          utc_offset_minutes: -420,
          local_date: '2026-03-08',
        }),
      ),
    ).toMatchObject({ reason: 'offset_zone_mismatch' });
    expect(resolveMeasurement(measurement({ local_date: '2026-10-12' }))).toMatchObject({
      reason: 'local_date_mismatch',
    });
    expect(resolveMeasurement(measurement({ iana_zone: 'Not/A Zone' }))).toMatchObject({
      reason: 'invalid_zone',
    });
    expect(resolveMeasurement(measurement({ local_date: 'yesterday' }))).toMatchObject({
      reason: 'ambiguous_local_date',
    });
  });

  it('creates, reads, corrects the same id, deletes, and reads the tombstone', async () => {
    const store = opened();
    const created = await act(store);
    expect(created).toMatchObject({
      ok: true,
      replayed: false,
      receipt: {
        action: 'create',
        record: {
          id: RECORD,
          revision: 1,
          weight_kg: '81.646627',
          input: { value: '180', unit: 'lb' },
          deleted_at: null,
        },
        cloud: { status: 'committed' },
        device: { healthkit: 'not_claimed' },
      },
    });
    const listed = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: {},
      store,
    });
    expect(listed).toMatchObject({ ok: true, records: [{ id: RECORD, revision: 1 }] });

    const corrected = await correctWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: LATER,
      body: createBody({
        operation_id: OP_2,
        value: 82.5,
        unit: 'kg',
        expected_revision: 1,
      }),
    });
    expect(corrected).toMatchObject({
      ok: true,
      receipt: { action: 'correct', record: { id: RECORD, revision: 2, weight_kg: '82.500000' } },
    });
    expect(store.entries.size).toBe(1);

    const removed = await deleteWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: LATER,
      body: { operation_id: OP_3, record_id: RECORD, expected_revision: 2 },
    });
    expect(removed).toMatchObject({
      ok: true,
      receipt: {
        action: 'delete',
        record: { id: RECORD, revision: 3, deleted_at: LATER.toISOString() },
        device: { healthkit: 'not_claimed' },
      },
    });
    const live = await listWeightEntries({ gateEnabled: true, subject: SUBJECT, query: {}, store });
    expect(live).toMatchObject({ ok: true, records: [] });
    const tombstone = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: { record_id: RECORD },
      store,
    });
    expect(tombstone).toMatchObject({
      ok: true,
      records: [{ id: RECORD, revision: 3, deleted_at: LATER.toISOString() }],
    });
    expect(store.audits.map((audit) => audit.action)).toEqual(['create', 'correct', 'delete']);
  });

  it('keeps two entries on the same local date', async () => {
    const store = opened();
    await act(store);
    const second = await act(
      store,
      createBody({
        operation_id: OP_2,
        record_id: RECORD_2,
        measured_at: '2026-10-13T21:00:00-07:00',
      }),
    );
    expect(second.ok).toBe(true);
    const listed = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: {},
      store,
    });
    expect(listed.ok && listed.records).toHaveLength(2);
  });

  it('replays a lost acknowledgement and a concurrent identical retry once', async () => {
    const store = opened();
    const [first, second] = await Promise.all([act(store), act(store)]);
    expect(store.mutations).toBe(1);
    expect(first.ok && second.ok).toBe(true);
    if (first.ok && second.ok) {
      expect(first.receipt).toEqual(second.receipt);
      expect([first.replayed, second.replayed].filter(Boolean)).toHaveLength(1);
    }
    const replay = await act(store);
    expect(replay).toMatchObject({ ok: true, replayed: true });
    if (first.ok && replay.ok) expect(replay.receipt).toEqual(first.receipt);
    expect(store.entries.size).toBe(1);
  });

  it('conflicts when the same operation id is reused with a different payload', async () => {
    const store = opened();
    await act(store);
    const changed = await act(store, createBody({ value: 181 }));
    expect(changed).toMatchObject({ ok: false, code: 'idempotency_conflict' });
    expect(store.mutations).toBe(1);
    expect(store.entries.get(RECORD)?.weight_kg).toBe('81.646627');
  });

  it('rejects a stale correction and does not turn it into a create', async () => {
    const store = opened();
    await act(store);
    await correctWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: LATER,
      body: createBody({ operation_id: OP_2, value: 82.5, unit: 'kg', expected_revision: 1 }),
    });
    const stale = await correctWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: LATER,
      body: createBody({ operation_id: OP_3, value: 70, unit: 'kg', expected_revision: 1 }),
    });
    expect(stale).toMatchObject({ ok: false, code: 'stale_revision' });
    expect(store.entries.get(RECORD)?.weight_kg).toBe('82.500000');
    expect(store.entries.size).toBe(1);
    expect(store.mutations).toBe(2);
  });

  it('replays a delete and distinguishes a stale revision from an already-deleted revision', async () => {
    const store = opened();
    await act(store);
    const removed = await deleteWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: LATER,
      body: { operation_id: OP_2, record_id: RECORD, expected_revision: 1 },
    });
    const replay = await deleteWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: new Date('2026-10-14T00:00:00.000Z'),
      body: { operation_id: OP_2, record_id: RECORD, expected_revision: 1 },
    });
    expect(replay).toMatchObject({ ok: true, replayed: true });
    if (removed.ok && replay.ok) expect(replay.receipt).toEqual(removed.receipt);
    expect(store.entries.get(RECORD)?.revision).toBe(2);
    const stale = await deleteWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: LATER,
      body: { operation_id: OP_3, record_id: RECORD, expected_revision: 1 },
    });
    const already = await deleteWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: LATER,
      body: {
        operation_id: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        record_id: RECORD,
        expected_revision: 2,
      },
    });
    expect(stale).toMatchObject({ code: 'stale_revision' });
    expect(already).toMatchObject({ code: 'already_deleted' });
    expect(store.mutations).toBe(2);
  });

  it('does not let another subject read, correct, or delete a record', async () => {
    const store = opened();
    store.setGrant(grantedSubject(OTHER, '22222222-2222-4222-8222-222222222222'));
    await act(store);
    const read = await listWeightEntries({
      gateEnabled: true,
      subject: OTHER,
      query: { record_id: RECORD },
      store,
    });
    const guessed = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: { record_id: '99999999-9999-4999-8999-999999999999' },
      store,
    });
    const corrected = await correctWeightEntry({
      gateEnabled: true,
      subject: OTHER,
      store,
      now: LATER,
      body: createBody({ operation_id: OP_2, expected_revision: 1, value: 90, unit: 'kg' }),
    });
    const removed = await deleteWeightEntry({
      gateEnabled: true,
      subject: OTHER,
      store,
      now: LATER,
      body: { operation_id: OP_3, record_id: RECORD, expected_revision: 1 },
    });
    expect(read).toMatchObject({ code: 'not_found' });
    expect(guessed).toMatchObject({ code: 'not_found' });
    expect(corrected).toMatchObject({ code: 'not_found' });
    expect(removed).toMatchObject({ code: 'not_found' });
    expect(store.entries.get(RECORD)?.subject).toBe(SUBJECT);
    expect(store.entries.get(RECORD)?.revision).toBe(1);
  });

  it('rejects a spoofed subject and invalid shapes before any write', async () => {
    const store = opened();
    const spoofed = await act(store, createBody({ subject: OTHER }));
    const user = await act(store, createBody({ user_id: OTHER }));
    const unit = await act(store, createBody({ unit: 'lbs' }));
    const text = await act(store, createBody({ value: '180' }));
    const missing = await act(store, { operation_id: OP, record_id: RECORD });
    expect(spoofed).toMatchObject({ code: 'spoofed_subject' });
    expect(user).toMatchObject({ code: 'spoofed_subject' });
    expect(unit).toMatchObject({ reason: 'rejected_shape' });
    expect(text).toMatchObject({ reason: 'rejected_shape' });
    expect(missing).toMatchObject({ reason: 'rejected_shape' });
    expect(store.mutations).toBe(0);
    const badRevision = await correctWeightEntry({
      gateEnabled: true,
      subject: SUBJECT,
      store,
      now: NOW,
      body: createBody({ expected_revision: 0 }),
    });
    expect(badRevision).toMatchObject({ reason: 'expected_revision' });
  });

  it('rejects admission failures and a closed gate without mutation', async () => {
    const store = opened();
    const calls = { grant: 0 };
    const closed: WeightLifecyclePort = {
      grant: async () => {
        calls.grant += 1;
        return grantedSubject(SUBJECT);
      },
      create: async () => {
        throw new Error('mutated');
      },
      correct: async () => {
        throw new Error('mutated');
      },
      remove: async () => {
        throw new Error('mutated');
      },
      list: async () => {
        throw new Error('mutated');
      },
    };
    await expect(
      createWeightEntry({
        gateEnabled: false,
        subject: SUBJECT,
        body: createBody(),
        store: closed,
        now: NOW,
      }),
    ).resolves.toMatchObject({ code: 'gate_off' });
    expect(calls.grant).toBe(0);

    const cases: Array<[string, Partial<ReturnType<typeof grantedSubject>>]> = [
      ['unconnected', { connected: false }],
      ['revoked', { revoked: true }],
      ['account_deleted', { accountDeleted: true }],
      ['account_not_found', { ownerId: null }],
      ['consent_required', { consentGranted: false }],
      ['ineligible', { entitled: false }],
    ];
    for (const [code, patch] of cases) {
      store.setGrant({ ...grantedSubject(SUBJECT), ...patch });
      const result = await act(store, createBody({ operation_id: OP_2, record_id: RECORD_2 }));
      expect(result).toMatchObject({ code });
    }
    expect(store.mutations).toBe(0);
    expect(store.entries.size).toBe(0);
  });

  it('pages by measured instant and rejects an unbounded or corrupt cursor', async () => {
    const store = opened();
    await act(store, createBody({ measured_at: '2026-10-13T08:00:00-07:00' }));
    await act(
      store,
      createBody({
        operation_id: OP_2,
        record_id: RECORD_2,
        measured_at: '2026-10-13T09:00:00-07:00',
      }),
    );
    await act(
      store,
      createBody({
        operation_id: OP_3,
        record_id: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        measured_at: '2026-10-13T07:00:00-07:00',
      }),
    );
    const first = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: { limit: 1 },
      store,
    });
    expect(first.ok && first.records.map((record) => record.id)).toEqual([RECORD_2]);
    expect(first.ok && first.next_cursor).toEqual(expect.any(String));
    const second = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: { limit: 1, cursor: first.ok ? first.next_cursor : '' },
      store,
    });
    expect(second.ok && second.records.map((record) => record.id)).toEqual([RECORD]);
    const badLimit = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: { limit: 101 },
      store,
    });
    const badCursor = await listWeightEntries({
      gateEnabled: true,
      subject: SUBJECT,
      query: { cursor: '%%%' },
      store,
    });
    expect(badLimit).toMatchObject({ reason: 'invalid_limit' });
    expect(badCursor).toMatchObject({ reason: 'invalid_cursor' });
  });

  it('keeps a tombstone dead and refuses a stale or different native payload', () => {
    const live: NativePushExisting = {
      user_subject: SUBJECT,
      deleted_at: null,
      client_updated_at: '2026-10-13T15:00:00.000Z',
      weight: 81.646627,
      weight_unit: 'kg',
      measured_at: '2026-10-13T15:00:00.000Z',
      local_date: '2026-10-13',
    };
    expect(decideNativePush(null, live)).toEqual({ kind: 'insert' });
    expect(decideNativePush({ ...live, user_subject: OTHER }, live)).toEqual({ kind: 'foreign' });
    expect(
      decideNativePush(
        { ...live, deleted_at: LATER.toISOString() },
        { ...live, client_updated_at: '2026-10-13T18:00:00.000Z' },
      ),
    ).toEqual({
      kind: 'conflict',
      code: 'tombstone',
    });
    expect(
      decideNativePush(live, {
        ...live,
        client_updated_at: '2026-10-13T18:00:00.000Z',
        weight: 82,
      }),
    ).toEqual({
      kind: 'accept',
      replay: false,
    });
    expect(decideNativePush(live, live)).toEqual({ kind: 'accept', replay: true });
    expect(
      decideNativePush(live, {
        ...live,
        client_updated_at: '2026-10-13T14:00:00.000Z',
        weight: 70,
      }),
    ).toEqual({
      kind: 'conflict',
      code: 'stale_write',
    });
    expect(decideNativePush(live, { ...live, weight: 70 })).toEqual({
      kind: 'conflict',
      code: 'payload_conflict',
    });
  });

  it('stays closed unless both env switches and an explicit gate are open', () => {
    expect(delegatedMetricsEnabled({})).toBe(false);
    expect(
      delegatedMetricsEnabled({
        LYB_METRICS_AGENT_ENABLED: 'true',
        LYB_CHATGPT_MCP_ENABLED: 'true',
      }),
    ).toBe(false);
    expect(
      delegatedMetricsEnabled({
        LYB_METRICS_AGENT_ENABLED: 'true',
        LYB_HYPERTROPHY_COACH_API_ENABLED: 'true',
        LYB_DELEGATED_PROGRAMMING_ENABLED: 'true',
      }),
    ).toBe(false);
    expect(
      delegatedMetricsEnabled(
        { LYB_METRICS_AGENT_ENABLED: 'true', LYB_CHATGPT_MCP_ENABLED: 'true' },
        true,
      ),
    ).toBe(true);
    expect(
      delegatedMetricsEnabled({
        LYB_METRICS_AGENT_ENABLED: 'true',
        LYB_CHATGPT_MCP_ENABLED: 'true',
        LYB_METRICS_AGENT_GATE_OVERRIDE: 'on',
      }),
    ).toBe(true);
    expect(
      delegatedMetricsEnabled(
        {
          LYB_METRICS_AGENT_ENABLED: 'true',
          LYB_CHATGPT_MCP_ENABLED: 'true',
          LYB_METRICS_AGENT_GATE_OVERRIDE: 'off',
        },
        true,
      ),
    ).toBe(false);
  });
});
