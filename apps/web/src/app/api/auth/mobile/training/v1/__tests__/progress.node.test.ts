/** @jest-environment node */

import { NextRequest } from 'next/server';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { createTrainingRouteHandlers, TRAINING_API_VERSION } from '../route-handlers';

const tokens: Record<string, string> = { 'token-a': 'subject-a', 'token-b': 'subject-b' };

function makeHarness(options: { enabled?: boolean; rateLimited?: boolean } = {}) {
  const records = new MemoryTrainingRecords();
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
    createId: () => '11111111-1111-4111-8111-000000000001',
    now: () => new Date('2026-01-10T12:00:00.000Z'),
    enabled: () => options.enabled ?? true,
  });
  return { handlers, records };
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

async function activeCount(
  records: MemoryTrainingRecords,
  subject: string,
  collection: 'training_sessions' | 'logged_sets' | 'training_feedback',
) {
  const pulled = await records.pull(subject, collection, {
    since: '1970-01-01T00:00:00.000Z',
    after_id: null,
  });
  return pulled.records.filter((row) => row.deleted_at === null);
}

describe('GET /api/auth/mobile/training/v1/progress', () => {
  it('rejects unauthenticated, disabled, and rate-limited reads', async () => {
    const unauthorized = makeHarness();
    expect((await unauthorized.handlers.progress(request('GET', 'progress'))).status).toBe(401);
    const disabled = makeHarness({ enabled: false });
    expect((await disabled.handlers.progress(request('GET', 'progress', 'token-a'))).status).toBe(
      404,
    );
    const limited = makeHarness({ rateLimited: true });
    const response = await limited.handlers.progress(request('GET', 'progress', 'token-a'));
    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('30');
  });

  it('reports history without creating a session and keeps another subject empty', async () => {
    const { handlers, records } = makeHarness();
    const before = await activeCount(records, 'subject-a', 'training_sessions');
    const empty = await handlers.progress(request('GET', 'progress', 'token-a'));
    expect(empty.status).toBe(200);
    await expect(empty.json()).resolves.toMatchObject({
      version: TRAINING_API_VERSION,
      enrolled: false,
      completedSessions: 0,
      exercises: [],
      decision: null,
    });
    expect(await activeCount(records, 'subject-a', 'training_sessions')).toEqual(before);

    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const enrolled = await handlers.progress(request('GET', 'progress', 'token-a'));
    expect(enrolled.status).toBe(200);
    const enrolledBody = await enrolled.json();
    expect(enrolledBody.enrolled).toBe(true);
    expect(enrolledBody.exercises).toEqual([]);
    expect(await activeCount(records, 'subject-a', 'training_sessions')).toEqual([]);

    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const exercise = session.exercises[0];
    const set = {
      sessionId: session.id,
      exerciseId: exercise.id,
      setNumber: 1,
      reps: 10,
      loadKg: 15,
      rir: 3,
    };
    const logged = await (await handlers.logSet(request('POST', 'log-set', 'token-a', set))).json();
    const sessionsAfterLog = await activeCount(records, 'subject-a', 'training_sessions');
    const progress = await handlers.progress(request('GET', 'progress', 'token-a'));
    expect(progress.status).toBe(200);
    const body = await progress.json();
    expect(body).toMatchObject({
      version: TRAINING_API_VERSION,
      enrolled: true,
      setsLast7Days: 1,
      exercises: [
        {
          exerciseId: exercise.id,
          name: exercise.name,
          lastSession: [{ setNumber: 1, reps: 10, loadKg: 15, rir: 3 }],
          heaviestSet: { reps: 10, loadKg: 15 },
        },
      ],
    });
    expect(body.evidence.sessions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sessionId: session.id,
          prescriptionId: session.id,
          status: 'in_progress',
          exercises: expect.arrayContaining([
            expect.objectContaining({
              exerciseId: exercise.id,
              variantId: exercise.id,
              status: 'completed',
              sets: [expect.objectContaining({ id: logged.log.id, status: 'completed', reps: 10 })],
            }),
          ]),
        }),
      ]),
    );
    expect(body.decision?.actor).toBe('controller');
    expect(JSON.stringify(body)).not.toMatch(/hypertrophy from|muscle growth/i);
    expect(await activeCount(records, 'subject-a', 'training_sessions')).toEqual(sessionsAfterLog);
    const other = await handlers.progress(request('GET', 'progress', 'token-b'));
    await expect(other.json()).resolves.toMatchObject({ enrolled: false, exercises: [] });
  });
});
