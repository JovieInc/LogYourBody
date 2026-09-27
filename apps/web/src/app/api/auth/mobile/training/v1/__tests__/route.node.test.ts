/** @jest-environment node */

import { NextRequest } from 'next/server';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import {
  NATIVE_PRODUCT_RECORD_COLLECTIONS,
  type NativeProductRecord,
  type NativeProductRecordCollection,
  type NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { createTrainingRouteHandlers } from '../route-handlers';
import { TRAINING_API_VERSION } from '../route-handlers';

const tokens: Record<string, string> = { 'token-a': 'subject-a', 'token-b': 'subject-b' };

class MemoryTrainingRecords implements NativeProductRecordsPort {
  private readonly data = Object.fromEntries(
    NATIVE_PRODUCT_RECORD_COLLECTIONS.map((collection) => [
      collection,
      new Map<string, NativeProductRecord>(),
    ]),
  ) as Record<NativeProductRecordCollection, Map<string, NativeProductRecord>>;

  async push(
    subject: string,
    collection: NativeProductRecordCollection,
    records: Array<Record<string, unknown>>,
  ) {
    const accepted: NativeProductRecord[] = [];
    const rejected_ids: string[] = [];
    for (const record of records) {
      const id = typeof record.id === 'string' ? record.id : '';
      if (!id) continue;
      const existing = this.data[collection].get(id);
      if (existing && existing.user_id !== subject) {
        rejected_ids.push(id);
        continue;
      }
      const stored = {
        ...record,
        id,
        user_id: subject,
        deleted_at: null,
        server_updated_at: '2026-01-10T12:00:00.000Z',
      } as NativeProductRecord;
      this.data[collection].set(id, stored);
      accepted.push(stored);
    }
    return { records: accepted, rejected_ids };
  }

  async pull(subject: string, collection: NativeProductRecordCollection) {
    const records = [...this.data[collection].values()].filter(
      (record) => record.user_id === subject,
    );
    return {
      records,
      deleted_ids: records.filter((record) => record.deleted_at).map((record) => record.id),
      next_cursor: null,
    };
  }

  async remove(subject: string, collection: NativeProductRecordCollection, ids: string[]) {
    const deleted_ids: string[] = [];
    for (const id of ids) {
      const record = this.data[collection].get(id);
      if (record?.user_id === subject) {
        this.data[collection].set(id, { ...record, deleted_at: '2026-01-10T12:01:00.000Z' });
        deleted_ids.push(id);
      }
    }
    return { deleted_ids };
  }

  async endActiveGlp1Medications() {
    return { updated: 0 };
  }

  async listAll(subject: string) {
    return Object.fromEntries(
      NATIVE_PRODUCT_RECORD_COLLECTIONS.map((collection) => [
        collection,
        [...this.data[collection].values()].filter(
          (record) => record.user_id === subject && !record.deleted_at,
        ),
      ]),
    ) as Record<NativeProductRecordCollection, NativeProductRecord[]>;
  }

  async deleteAllForSubject(subject: string) {
    for (const records of Object.values(this.data)) {
      for (const [id, record] of records) if (record.user_id === subject) records.delete(id);
    }
  }
}

function makeHarness(options: { enabled?: boolean; rateLimited?: boolean } = {}) {
  const records = new MemoryTrainingRecords();
  let currentTime = new Date('2026-01-10T12:00:00.000Z');
  let nextId = 1;
  const handlers = createTrainingRouteHandlers({
    authenticate: async (request) => {
      const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
      const subject = token ? tokens[token] : undefined;
      return subject ? ({ sub: subject } as JovieUserInfo) : null;
    },
    records,
    users: {
      getUser: async () => ({ profileData: { date_of_birth: '1990-01-01' } }) as never,
    } as never,
    reserveRequest: async () =>
      options.rateLimited
        ? { allowed: false, retryAfterSeconds: 30 }
        : { allowed: true, remainingInWindow: 9, remainingToday: 99 },
    createId: () => `11111111-1111-4111-8111-${String(nextId++).padStart(12, '0')}`,
    now: () => currentTime,
    enabled: () => options.enabled ?? true,
  });
  return {
    handlers,
    records,
    setNow: (value: string) => {
      currentTime = new Date(value);
    },
  };
}

function request(method: string, path: string, token?: string, body?: unknown) {
  return new NextRequest(`http://localhost/api/auth/mobile/training/v1/${path}`, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

const eligibleSetup = {
  adultConfirmed: true,
  safetyConfirmed: true,
  sessionsPerWeek: 2,
  equipment: 'dumbbells',
};

describe('authenticated training API', () => {
  it('rejects unauthenticated access, disabled rollout, and rate-limited requests', async () => {
    const unauthorized = makeHarness();
    expect((await unauthorized.handlers.next(request('GET', 'next'))).status).toBe(401);

    const disabled = makeHarness({ enabled: false });
    expect((await disabled.handlers.next(request('GET', 'next', 'token-a'))).status).toBe(404);

    const limited = makeHarness({ rateLimited: true });
    const response = await limited.handlers.next(request('GET', 'next', 'token-a'));
    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('30');
  });

  it('requires safety opt-in and stores a subject-scoped program before producing a plan', async () => {
    const { handlers, records } = makeHarness();
    expect((await handlers.next(request('GET', 'next', 'token-a'))).status).toBe(409);
    expect(
      (
        await handlers.enroll(
          request('POST', 'enroll', 'token-a', { ...eligibleSetup, adultConfirmed: false }),
        )
      ).status,
    ).toBe(403);

    const enrolled = await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    expect(enrolled.status).toBe(201);
    await expect(enrolled.json()).resolves.toMatchObject({
      version: TRAINING_API_VERSION,
      program: {
        consentVersion: 'hypertrophy-coach-v1',
        sessionsPerWeek: 2,
        equipment: 'dumbbells',
      },
    });
    const first = await handlers.next(request('GET', 'next', 'token-a'));
    const firstBody = await first.json();
    expect(first.status).toBe(200);
    expect(firstBody.session).toMatchObject({ pattern: 'A', exercises: expect.any(Array) });
    expect(firstBody.weekCount).toBe(4);
    expect(firstBody.session.exercises[0].targetLoadKg).toBeNull();

    const second = await handlers.next(request('GET', 'next', 'token-a'));
    await expect(second.json()).resolves.toMatchObject({ session: { id: firstBody.session.id } });
    expect(
      (
        await records.pull('subject-b', 'training_sessions', {
          since: '1970-01-01T00:00:00.000Z',
          after_id: null,
        })
      ).records,
    ).toEqual([]);
  });

  it('fails closed when the profile does not confirm an adult account', async () => {
    const records = new MemoryTrainingRecords();
    const handlers = createTrainingRouteHandlers({
      authenticate: async () => ({ sub: 'subject-a' }) as JovieUserInfo,
      records,
      users: { getUser: async () => ({ profileData: { date_of_birth: '2010-01-01' } }) } as never,
      reserveRequest: async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }),
      createId: () => '11111111-1111-4111-8111-000000000001',
      now: () => new Date('2026-01-10T12:00:00.000Z'),
      enabled: () => true,
    });
    expect(
      (await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup))).status,
    ).toBe(403);
    expect(
      (
        await records.pull('subject-a', 'training_feedback', {
          since: '1970-01-01T00:00:00.000Z',
          after_id: null,
        })
      ).records,
    ).toEqual([]);
  });

  it('stores only valid set logs for the authenticated active prescription', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const nextBody = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const session = nextBody.session;
    const exerciseId = session.exercises[0].id;
    const set = { sessionId: session.id, exerciseId, setNumber: 1, reps: 10, loadKg: 15, rir: 3 };

    expect(
      (await handlers.logSet(request('POST', 'log-set', 'token-a', { ...set, setNumber: 3 })))
        .status,
    ).toBe(400);
    const response = await handlers.logSet(request('POST', 'log-set', 'token-a', set));
    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      log: { sessionId: session.id, exerciseId, setNumber: 1 },
    });
    const stored = await records.pull('subject-a', 'logged_sets', {
      since: '1970-01-01T00:00:00.000Z',
      after_id: null,
    });
    expect(stored.records).toHaveLength(1);
    expect((await handlers.logSet(request('POST', 'log-set', 'token-a', set))).status).toBe(201);
    expect(
      (
        await records.pull('subject-a', 'logged_sets', {
          since: '1970-01-01T00:00:00.000Z',
          after_id: null,
        })
      ).records,
    ).toHaveLength(1);
    expect(
      (
        await records.pull('subject-b', 'logged_sets', {
          since: '1970-01-01T00:00:00.000Z',
          after_id: null,
        })
      ).records,
    ).toEqual([]);
    expect((await handlers.logSet(request('POST', 'log-set', 'token-b', set))).status).toBe(409);
  });

  it('uses feedback conservatively and revokes all program records on opt-out', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const firstBody = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const feedback = await handlers.feedback(
      request('POST', 'feedback', 'token-a', {
        sessionId: firstBody.session.id,
        soreness: 3,
        pump: 1,
        performance: 'stable',
        jointPain: 5,
      }),
    );
    expect(feedback.status).toBe(201);
    const paused = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(paused.session.safetyStop).toBe(true);
    expect(paused.session.exercises).toEqual([]);

    expect(
      (
        await handlers.feedback(
          request('POST', 'feedback', 'token-a', {
            sessionId: firstBody.session.id,
            soreness: 1,
            pump: 4,
            performance: 'stable',
            jointPain: 0,
          }),
        )
      ).status,
    ).toBe(201);
    const resumed = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(resumed.session.safetyStop).toBe(false);
    expect(resumed.session.exercises.length).toBeGreaterThan(0);

    const revoked = await handlers.revoke(request('DELETE', 'enroll', 'token-a'));
    expect(revoked.status).toBe(200);
    expect((await handlers.next(request('GET', 'next', 'token-a'))).status).toBe(409);
    for (const collection of ['training_sessions', 'logged_sets', 'training_feedback'] as const) {
      const remaining = await records.pull('subject-a', collection, {
        since: '1970-01-01T00:00:00.000Z',
        after_id: null,
      });
      expect(remaining.records.every((record) => record.deleted_at !== null)).toBe(true);
    }
  });
});
