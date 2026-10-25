/** @jest-environment node */

import { NextRequest } from 'next/server';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import { MemoryTrainingRecords } from '@/lib/training/memory-records.testing';
import { createTrainingRouteHandlers } from '../route-handlers';
import { TRAINING_API_VERSION } from '../route-handlers';

const tokens: Record<string, string> = { 'token-a': 'subject-a', 'token-b': 'subject-b' };

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
  it('protects progress reads with authentication, rollout and rate limits before reading records', async () => {
    for (const [options, token, status] of [
      [{}, undefined, 401],
      [{ enabled: false }, 'token-a', 404],
      [{ rateLimited: true }, 'token-a', 429],
    ] as const) {
      const { handlers, records } = makeHarness(options);
      const pull = jest.spyOn(records, 'pull');
      const response = await handlers.progress(request('GET', 'progress', token));
      expect(response.status).toBe(status);
      expect(response.headers.get('cache-control')).toBe('no-store');
      if (status === 429) expect(response.headers.get('retry-after')).toBe('30');
      expect(pull).not.toHaveBeenCalled();
    }
  });

  it('reads the shared subject-scoped history without starting sessions or writing records', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const set = {
      sessionId: session.id,
      exerciseId: session.exercises[0].id,
      setNumber: 1,
      reps: 10,
      loadKg: 15,
      rir: 3,
    };
    await handlers.logSet(request('POST', 'log-set', 'token-a', set));
    const correction = {
      ...set,
      reps: 8,
      loadKg: 12,
      expectedRevision: 0,
      correctionId: '22222222-2222-4222-8222-000000000001',
    };
    const corrected = await (
      await handlers.correctSet(request('POST', 'correct-set', 'token-a', correction))
    ).json();
    const push = jest.spyOn(records, 'push');
    const commit = jest.spyOn(records.trainingMutations, 'commit');
    const response = await handlers.progress(request('GET', 'progress', 'token-a'));
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    const body = await response.json();
    expect(body).toMatchObject({
      version: 1,
      progress: {
        enrolled: true,
        completedSessions: 0,
        setsLast7Days: 1,
        exercises: [
          { exerciseId: set.exerciseId, lastSession: [corrected.log], heaviestSet: corrected.log },
        ],
        sessions: [{ sessionId: session.id, status: 'in_progress', sets: [corrected.log] }],
      },
    });
    expect(push).not.toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
    const other = await handlers.progress(request('GET', 'progress', 'token-b'));
    await expect(other.json()).resolves.toEqual({
      version: 1,
      progress: {
        enrolled: false,
        completedSessions: 0,
        setsLast7Days: 0,
        exercises: [],
        sessions: [],
        latestCheckIn: null,
      },
    });
  });

  it('fails closed on a progress store outage and returns no partial history', async () => {
    const { handlers, records } = makeHarness();
    jest.spyOn(records, 'pull').mockRejectedValue(new Error('private database details'));
    const response = await handlers.progress(request('GET', 'progress', 'token-a'));
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({ version: 1, error: 'training_unavailable' });
  });

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

  it('reorders before substituting and rejects stale current-card actions', async () => {
    const { handlers } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const firstId = session.exercises[0].id;
    const eventId = '22222222-2222-4222-8222-000000000001';
    const reordered = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId,
        expectedRevision: 0,
        action: { kind: 'equipment_unavailable', exerciseId: firstId },
      }),
    );
    expect(reordered.status).toBe(200);
    const body = await reordered.json();
    expect(body.decision).toBe('reordered');
    expect(body.session.exercises.at(-1).id).toBe(firstId);
    expect(body.session.executionRevision).toBe(1);

    const retry = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId,
        expectedRevision: 0,
        action: { kind: 'equipment_unavailable', exerciseId: firstId },
      }),
    );
    await expect(retry.json()).resolves.toMatchObject({
      decision: 'reordered',
      session: { executionRevision: 1 },
    });

    const stale = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '22222222-2222-4222-8222-000000000002',
        expectedRevision: 0,
        action: { kind: 'skip', exerciseId: firstId },
      }),
    );
    expect(stale.status).toBe(409);
    await expect(stale.json()).resolves.toMatchObject({ error: 'stale_revision' });

    const staleCurrent = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '22222222-2222-4222-8222-000000000004',
        expectedRevision: 1,
        action: { kind: 'skip', exerciseId: firstId },
      }),
    );
    expect(staleCurrent.status).toBe(409);
    await expect(staleCurrent.json()).resolves.toMatchObject({
      error: 'stale_current_exercise',
    });

    const ended = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '22222222-2222-4222-8222-000000000003',
        expectedRevision: 1,
        action: { kind: 'end' },
      }),
    );
    expect(ended.status).toBe(200);
    const endedRetry = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '22222222-2222-4222-8222-000000000003',
        expectedRevision: 1,
        action: { kind: 'end' },
      }),
    );
    expect(endedRetry.status).toBe(200);
    await expect(endedRetry.json()).resolves.toMatchObject({
      decision: 'ended',
      session: { id: session.id, executionRevision: 2 },
    });
    const next = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(next.session.id).not.toBe(session.id);
    expect(next.session).toMatchObject({ executionRevision: 0, executionEvents: [] });
  });

  it('uses only engine-eligible substitutions with no invented load after bounded shortening', async () => {
    const { handlers } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const shortened = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '33333333-3333-4333-8333-000000000001',
        expectedRevision: 0,
        action: { kind: 'shorten', minutes: 5 },
      }),
    );
    const shortenedBody = await shortened.json();
    expect(shortenedBody.decision).toBe('shortened');
    expect(shortenedBody.session.exercises).toHaveLength(1);
    expect(shortenedBody.session.exercises[0].sets).toBe(1);

    const original = shortenedBody.session.exercises[0];
    const substituted = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '33333333-3333-4333-8333-000000000002',
        expectedRevision: 1,
        action: { kind: 'equipment_unavailable', exerciseId: original.id },
      }),
    );
    expect(substituted.status).toBe(200);
    const substitutedBody = await substituted.json();
    expect(substitutedBody.decision).toBe('substituted');
    expect(substitutedBody.session.exercises[0]).toMatchObject({
      id: original.substitutions[0].id,
      primaryMuscle: original.primaryMuscle,
      targetLoadKg: null,
      progression: 'hold',
      sets: 1,
    });
    expect(substitutedBody.session.exercises[0].id).not.toBe(original.id);
  });

  it('applies the exact reviewed card alternative once without rebuilding the workout', async () => {
    const { handlers } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const original = session.exercises[0];
    const alternative = original.substitutions.at(-1);
    expect(alternative).toBeDefined();
    const action = {
      sessionId: session.id,
      eventId: '33333333-3333-4333-8333-000000000010',
      expectedRevision: 0,
      action: { kind: 'swap', exerciseId: original.id, replacementExerciseId: alternative.id },
    };
    expect((await handlers.action(request('POST', 'action', 'token-b', action))).status).toBe(409);
    const response = await handlers.action(request('POST', 'action', 'token-a', action));
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.session.exercises[0]).toMatchObject({
      id: alternative.id,
      sets: original.sets,
      targetLoadKg: null,
    });
    expect(body.session.exercises[0].setup).toMatchObject({
      requires: expect.any(Array),
      bodyPosition: expect.any(String),
      trunkDemand: { basis: 'reviewed', level: expect.any(String), note: expect.any(String) },
    });
    expect(body.session.exercises.slice(1)).toEqual(session.exercises.slice(1));
    expect(body.session.executionRevision).toBe(1);
    const retry = await handlers.action(request('POST', 'action', 'token-a', action));
    expect((await retry.json()).session.executionEvents).toHaveLength(1);
    const persisted = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(persisted.session.exercises[0].id).toBe(alternative.id);
    const stale = { ...action, eventId: '33333333-3333-4333-8333-000000000011' };
    expect((await handlers.action(request('POST', 'action', 'token-a', stale))).status).toBe(409);
  });

  it('rejects unapproved card alternatives, unknown actions and generated code without writing', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const push = jest.spyOn(records.trainingMutations, 'commit');
    for (const action of [
      { kind: 'swap', exerciseId: session.exercises[0].id, replacementExerciseId: 'invented' },
      { kind: 'run_code', code: 'return true' },
      { kind: 'pause', code: 'return true' },
    ]) {
      const result = await handlers.action(
        request('POST', 'action', 'token-a', {
          sessionId: session.id,
          eventId: '33333333-3333-4333-8333-000000000012',
          expectedRevision: 0,
          action,
        }),
      );
      expect(result.status).toBeGreaterThanOrEqual(400);
    }
    expect(push).not.toHaveBeenCalled();
  });

  it('fails closed when a persisted session injects an invalid substitution', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const shortened = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '33333333-3333-4333-8333-000000000010',
        expectedRevision: 0,
        action: { kind: 'shorten', minutes: 5 },
      }),
    );
    expect(shortened.status).toBe(200);
    const rows = await records.pull('subject-a', 'training_sessions');
    const row = rows.records.find((candidate) => candidate.id === session.id)!;
    const prescription = row.prescription as typeof session;
    const exercise = prescription.exercises[0];
    await records.push('subject-a', 'training_sessions', [
      {
        ...row,
        prescription: {
          ...prescription,
          exercises: [
            {
              ...exercise,
              substitutions: [
                {
                  ...exercise.substitutions[0],
                  id: 'unverified_shoulders_machine',
                  name: 'Unverified shoulders machine',
                  primaryMuscle: 'shoulders',
                  targetLoadKg: 100,
                },
              ],
            },
          ],
        },
      },
    ]);

    const response = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '33333333-3333-4333-8333-000000000011',
        expectedRevision: 1,
        action: { kind: 'equipment_unavailable', exerciseId: exercise.id },
      }),
    );
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({
      error: 'no_eligible_substitution',
    });
  });

  it('admits only one concurrent action for an execution revision', async () => {
    const { handlers } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const responses = await Promise.all([
      handlers.action(
        request('POST', 'action', 'token-a', {
          sessionId: session.id,
          eventId: '66666666-6666-4666-8666-000000000001',
          expectedRevision: 0,
          action: { kind: 'pause' },
        }),
      ),
      handlers.action(
        request('POST', 'action', 'token-a', {
          sessionId: session.id,
          eventId: '66666666-6666-4666-8666-000000000002',
          expectedRevision: 0,
          action: { kind: 'shorten', minutes: 30 },
        }),
      ),
    ]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 409]);
    const next = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(next.session.executionRevision).toBe(1);
    expect(next.session.executionEvents).toHaveLength(1);
  });

  it('rejects an interruption decision if the current set changes before its atomic write', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const update = records.updateTrainingSession.bind(records);
    jest
      .spyOn(records, 'updateTrainingSession')
      .mockImplementationOnce(async (subject, id, revision, setCount, row) => {
        await handlers.logSet(
          request('POST', 'log-set', 'token-a', {
            sessionId: session.id,
            exerciseId: session.exercises[0].id,
            setNumber: 1,
            reps: 10,
            loadKg: 20,
            rir: 3,
          }),
        );
        return update(subject, id, revision, setCount, row);
      });
    const response = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '77777777-7777-4777-8777-000000000001',
        expectedRevision: 0,
        action: {
          kind: 'equipment_unavailable',
          exerciseId: session.exercises[0].id,
        },
      }),
    );
    expect(response.status).toBe(409);
    const next = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(next.session.executionRevision).toBe(0);
    expect(next.session.loggedSets).toHaveLength(1);
    expect(next.session.exercises[0].id).toBe(session.exercises[0].id);
  });

  it('keeps situational events session-scoped and enters the pain safety path', async () => {
    const { handlers } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const pain = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '44444444-4444-4444-8444-000000000001',
        expectedRevision: 0,
        action: { kind: 'pain', exerciseId: session.exercises[0].id },
      }),
    );
    expect(pain.status).toBe(200);
    await expect(pain.json()).resolves.toMatchObject({
      decision: 'pain',
      session: {
        id: session.id,
        safetyStop: true,
        executionPaused: true,
        executionEvents: [{ kind: 'pain', exerciseId: session.exercises[0].id }],
      },
    });
    const resumed = await handlers.next(request('GET', 'next', 'token-a'));
    await expect(resumed.json()).resolves.toMatchObject({
      session: { id: session.id, safetyStop: true, executionRevision: 1 },
    });
    const ended = await handlers.action(
      request('POST', 'action', 'token-a', {
        sessionId: session.id,
        eventId: '44444444-4444-4444-8444-000000000002',
        expectedRevision: 1,
        action: { kind: 'end' },
      }),
    );
    expect(ended.status).toBe(200);
    await expect(ended.json()).resolves.toMatchObject({ decision: 'ended' });
  });

  it('keeps the first active-session set immutable across conflicts and delayed retries', async () => {
    const { handlers, records, setNow } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const set = {
      sessionId: session.id,
      exerciseId: session.exercises[0].id,
      setNumber: 1,
      reps: 10,
      loadKg: 20,
      rir: 3,
    };
    const first = await handlers.logSet(request('POST', 'log-set', 'token-a', set));
    expect(first.status).toBe(201);
    const firstBody = await first.json();
    setNow('2026-01-10T12:01:00.000Z');
    const conflict = await handlers.logSet(
      request('POST', 'log-set', 'token-a', {
        ...set,
        reps: 8,
        loadKg: 25,
      }),
    );
    expect(conflict.status).toBe(409);
    await expect(conflict.json()).resolves.toMatchObject({ error: 'set_conflict' });
    setNow('2026-01-10T12:02:00.000Z');
    const retry = await handlers.logSet(request('POST', 'log-set', 'token-a', set));
    expect(retry.status).toBe(201);
    await expect(retry.json()).resolves.toMatchObject({
      log: firstBody.log,
      sessionComplete: false,
    });
    expect((await records.pull('subject-a', 'logged_sets')).records).toEqual([firstBody.log]);
  });

  it('corrects the same set identity once with an atomic audit trail', async () => {
    const { handlers, records, setNow } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const set = {
      sessionId: session.id,
      exerciseId: session.exercises[0].id,
      setNumber: 1,
      reps: 10,
      loadKg: 20,
      rir: 2,
    };
    const logged = await (await handlers.logSet(request('POST', 'log-set', 'token-a', set))).json();
    expect(logged.log).toMatchObject({ revision: 0, corrections: [] });
    setNow('2026-01-10T12:01:00.000Z');
    const correction = {
      ...set,
      reps: 9,
      correctionId: '55555555-5555-4555-8555-000000000001',
      expectedRevision: 0,
    };
    const corrected = await handlers.correctSet(
      request('POST', 'correct-set', 'token-a', correction),
    );
    expect(corrected.status).toBe(200);
    await expect(corrected.json()).resolves.toMatchObject({
      log: {
        id: logged.log.id,
        reps: 9,
        revision: 1,
        corrections: [
          {
            id: correction.correctionId,
            previous: { reps: 10, loadKg: 20, rir: 2 },
          },
        ],
      },
    });
    const retry = await handlers.correctSet(request('POST', 'correct-set', 'token-a', correction));
    expect(retry.status).toBe(200);
    const stored = (await records.pull('subject-a', 'logged_sets')).records;
    expect(stored).toHaveLength(1);
    expect(stored[0].corrections).toHaveLength(1);
    const stale = await handlers.correctSet(
      request('POST', 'correct-set', 'token-a', {
        ...correction,
        correctionId: '55555555-5555-4555-8555-000000000002',
        reps: 8,
      }),
    );
    expect(stale.status).toBe(409);
    expect((await records.pull('subject-a', 'logged_sets')).records[0].reps).toBe(9);
  });

  it.each([false, true])(
    'atomically resolves concurrent set submissions (identical=%s)',
    async (identical) => {
      const { handlers, records } = makeHarness();
      await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
      const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
      const set = {
        sessionId: session.id,
        exerciseId: session.exercises[0].id,
        setNumber: 1,
        reps: 10,
        loadKg: 20,
        rir: 3,
      };
      const responses = await Promise.all([
        handlers.logSet(request('POST', 'log-set', 'token-a', set)),
        handlers.logSet(
          request('POST', 'log-set', 'token-a', {
            ...set,
            reps: identical ? 10 : 8,
          }),
        ),
      ]);
      expect(responses.map((response) => response.status).sort()).toEqual(
        identical ? [201, 201] : [201, 409],
      );
      const bodies = await Promise.all(responses.map((response) => response.json()));
      const accepted = bodies.filter((body) => body.log);
      const stored = (await records.pull('subject-a', 'logged_sets')).records;
      expect(stored).toHaveLength(1);
      for (const body of accepted) expect(body.log).toEqual(stored[0]);
      if (!identical) expect(bodies.find((body) => body.error)?.error).toBe('set_conflict');
    },
  );

  it('fails safely when atomic set insertion is unavailable', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    Object.defineProperty(records, 'insertTrainingSet', { value: undefined });
    const response = await handlers.logSet(
      request('POST', 'log-set', 'token-a', {
        sessionId: session.id,
        exerciseId: session.exercises[0].id,
        setNumber: 1,
        reps: 10,
        loadKg: 20,
        rir: 3,
      }),
    );
    expect(response.status).toBe(503);
    expect((await records.pull('subject-a', 'logged_sets')).records).toEqual([]);
  });

  it('acknowledges saved sets after effective volume changes without accepting edits or new out-of-plan sets', async () => {
    const { handlers, records, setNow } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const set = {
      sessionId: session.id,
      exerciseId: session.exercises[0].id,
      setNumber: 2,
      reps: 10,
      loadKg: 20,
      rir: 3,
    };
    const original = await (
      await handlers.logSet(request('POST', 'log-set', 'token-a', set))
    ).json();
    const storedSession = (await records.pull('subject-a', 'training_sessions')).records[0]!;
    await records.push('subject-a', 'training_sessions', [
      {
        ...storedSession,
        prescription: {
          ...session,
          exercises: session.exercises.map((exercise: { sets: number }) => ({
            ...exercise,
            sets: 1,
          })),
        },
      },
    ]);
    setNow('2026-01-10T12:02:00.000Z');
    const retry = await handlers.logSet(request('POST', 'log-set', 'token-a', set));
    expect(retry.status).toBe(201);
    await expect(retry.json()).resolves.toMatchObject({
      log: original.log,
      sessionComplete: false,
    });
    const changed = await handlers.logSet(
      request('POST', 'log-set', 'token-a', { ...set, reps: 8 }),
    );
    expect(changed.status).toBe(409);
    await expect(changed.json()).resolves.toMatchObject({ error: 'set_conflict' });
    const newSet = await handlers.logSet(
      request('POST', 'log-set', 'token-a', { ...set, exerciseId: session.exercises[1].id }),
    );
    expect(newSet.status).toBe(400);
    await expect(newSet.json()).resolves.toMatchObject({ error: 'set_not_in_session' });
    await handlers.enroll(request('POST', 'enroll', 'token-b', eligibleSetup));
    expect((await handlers.logSet(request('POST', 'log-set', 'token-b', set))).status).toBe(404);
    expect((await records.pull('subject-a', 'logged_sets')).records).toEqual([original.log]);
  });

  it.each(['deleted-before-read', 'deleted-before-insert', 'unsupported'])(
    'does not bypass atomic safety for an out-of-plan saved set retry (%s)',
    async (state) => {
      const { handlers, records } = makeHarness();
      await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
      const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
      const set = {
        sessionId: session.id,
        exerciseId: session.exercises[0].id,
        setNumber: 2,
        reps: 10,
        loadKg: 20,
        rir: 3,
      };
      const { log } = await (
        await handlers.logSet(request('POST', 'log-set', 'token-a', set))
      ).json();
      const storedSession = (await records.pull('subject-a', 'training_sessions')).records[0]!;
      await records.push('subject-a', 'training_sessions', [
        {
          ...storedSession,
          prescription: {
            ...session,
            exercises: session.exercises.map((exercise: { sets: number }) => ({
              ...exercise,
              sets: 1,
            })),
          },
        },
      ]);
      if (state === 'deleted-before-read') {
        await records.remove('subject-a', 'logged_sets', [log.id]);
      } else if (state === 'deleted-before-insert') {
        const insert = records.insertTrainingSet.bind(records);
        records.insertTrainingSet = async (subject, value) => {
          await records.remove(subject, 'logged_sets', [log.id]);
          return insert(subject, value);
        };
      } else {
        Object.defineProperty(records, 'insertTrainingSet', { value: undefined });
      }
      const response = await handlers.logSet(request('POST', 'log-set', 'token-a', set));
      expect(response.status).toBe(state === 'deleted-before-read' ? 400 : 503);
      const saved = (await records.pull('subject-a', 'logged_sets')).records;
      expect(saved).toHaveLength(1);
      expect(saved[0]).toEqual({
        ...log,
        deleted_at: state === 'unsupported' ? null : expect.any(String),
      });
    },
  );

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

  it('replays an identical recovery check-in without adding evidence or changing the saved time', async () => {
    const { handlers, records, setNow } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const checkIn = {
      sessionId: session.id,
      soreness: 8,
      pump: 4,
      performance: 'down',
      jointPain: 0,
    };
    const first = await handlers.feedback(request('POST', 'feedback', 'token-a', checkIn));
    expect(first.status).toBe(201);
    const saved = (await first.json()).feedback;
    setNow('2026-01-10T12:01:00.000Z');
    const retry = await handlers.feedback(request('POST', 'feedback', 'token-a', checkIn));
    expect(retry.status).toBe(201);
    await expect(retry.json()).resolves.toMatchObject({ feedback: saved });
    expect(
      (await records.pull('subject-a', 'training_feedback')).records.filter(
        (row) => row.record_type === 'session_feedback',
      ),
    ).toHaveLength(1);
    const reopened = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(reopened.session.exercises[0].sets).toBe(2);
  });

  it('accepts sparse native readiness observations and returns a typed next-set action', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const response = await handlers.feedback(
      request('POST', 'feedback', 'token-a', {
        sessionId: session.id,
        sourceObservationId: 'native-set-observation-1',
        targetMuscle: 'back',
        targetMuscleReadiness: 'ready',
        breathingReadiness: 'limited',
        context: {
          exerciseId: 'one_arm_dumbbell_row',
          setNumber: 2,
          setOrder: 4,
          loadKg: 25,
          reps: 10,
          rir: 2,
          restSeconds: 120,
          setFormat: 'straight',
        },
      }),
    );
    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      feedback: {
        source: 'touch',
        sourceObservationId: 'native-set-observation-1',
      },
      nextSetRecommendation: {
        scope: 'between_set',
        action: 'extend_rest',
        weeklyPlanChanged: false,
        safetyCertified: false,
      },
    });
    const saved = (await records.pull('subject-a', 'training_feedback')).records.find(
      (row) => row.record_type === 'session_feedback',
    );
    expect(saved).toMatchObject({ source: 'touch', context: { setNumber: 2, rir: 2 } });
    expect(saved).not.toHaveProperty('soreness');

    const manualLog = await handlers.logSet(
      request('POST', 'log-set', 'token-a', {
        sessionId: session.id,
        exerciseId: session.exercises[0].id,
        setNumber: 1,
        reps: 10,
        loadKg: 15,
        rir: 3,
      }),
    );
    expect(manualLog.status).toBe(201);
  });

  it('counts concurrent duplicate check-ins as one session of recovery evidence', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const checkIn = {
      sessionId: session.id,
      soreness: 8,
      pump: 4,
      performance: 'down',
      jointPain: 0,
    };
    const responses = await Promise.all([
      handlers.feedback(request('POST', 'feedback', 'token-a', checkIn)),
      handlers.feedback(request('POST', 'feedback', 'token-a', checkIn)),
    ]);
    expect(responses.map((response) => response.status)).toEqual([201, 201]);
    const saved = (await records.pull('subject-a', 'training_feedback')).records.filter(
      (row) => row.record_type === 'session_feedback',
    );
    expect(new Set(saved.map((row) => row.sessionId)).size).toBe(1);
    const reopened = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(reopened.session.exercises[0].sets).toBe(2);
  });

  it('does not move an old session retry ahead of a newer session pain check-in', async () => {
    const { handlers, records, setNow } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const earlier = {
      sessionId: session.id,
      soreness: 8,
      pump: 4,
      performance: 'down',
      jointPain: 0,
    };
    const first = await handlers.feedback(request('POST', 'feedback', 'token-a', earlier));
    const firstFeedback = (await first.json()).feedback;
    for (const exercise of session.exercises) {
      for (let setNumber = 1; setNumber <= exercise.sets; setNumber += 1) {
        expect(
          (
            await handlers.logSet(
              request('POST', 'log-set', 'token-a', {
                sessionId: session.id,
                exerciseId: exercise.id,
                setNumber,
                reps: 10,
                loadKg: 20,
                rir: 3,
              }),
            )
          ).status,
        ).toBe(201);
      }
    }
    setNow('2026-01-10T13:00:00.000Z');
    const { session: nextSession } = await (
      await handlers.next(request('GET', 'next', 'token-a'))
    ).json();
    expect(nextSession.id).not.toBe(session.id);
    expect(
      (
        await handlers.feedback(
          request('POST', 'feedback', 'token-a', {
            ...earlier,
            sessionId: nextSession.id,
            performance: 'stable',
            jointPain: 5,
          }),
        )
      ).status,
    ).toBe(201);
    setNow('2026-01-10T14:00:00.000Z');
    const retry = await handlers.feedback(request('POST', 'feedback', 'token-a', earlier));
    expect(retry.status).toBe(201);
    await expect(retry.json()).resolves.toMatchObject({ feedback: firstFeedback });
    expect(
      (await records.pull('subject-a', 'training_feedback')).records.filter(
        (row) => row.record_type === 'session_feedback',
      ),
    ).toHaveLength(2);
    const reopened = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(reopened.session.safetyStop).toBe(true);
  });

  it('restores acknowledged sets and their entered values when reopening an active session', async () => {
    const { handlers } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const set = {
      sessionId: session.id,
      exerciseId: session.exercises[0].id,
      setNumber: 1,
      reps: 11,
      loadKg: 22.5,
      rir: 2,
    };
    expect((await handlers.logSet(request('POST', 'log-set', 'token-a', set))).status).toBe(201);
    const reopened = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(reopened.session.id).toBe(session.id);
    expect(reopened.session.loggedSets).toEqual([expect.objectContaining(set)]);
    const otherAccount = await (await handlers.next(request('GET', 'next', 'token-b'))).json();
    expect(otherAccount.session).toBeUndefined();
  });

  it('retains an unfinished prescription through logging, pain pause, next-week resume and opt-out', async () => {
    const { handlers, setNow } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session: original } = await (
      await handlers.next(request('GET', 'next', 'token-a'))
    ).json();
    const set = {
      sessionId: original.id,
      exerciseId: original.exercises[0].id,
      reps: 10,
      loadKg: 25,
      rir: 4,
    };
    for (const setNumber of [1, 2]) {
      expect(
        (await handlers.logSet(request('POST', 'log-set', 'token-a', { ...set, setNumber })))
          .status,
      ).toBe(201);
    }
    const reopened = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(reopened.session.exercises).toEqual(original.exercises);
    const checkIn = {
      sessionId: original.id,
      soreness: 2,
      pump: 5,
      performance: 'stable',
      jointPain: 5,
    };
    expect((await handlers.feedback(request('POST', 'feedback', 'token-a', checkIn))).status).toBe(
      201,
    );
    const paused = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(paused.session).toMatchObject({ id: original.id, safetyStop: true, exercises: [] });
    expect(
      (
        await handlers.logSet(
          request('POST', 'log-set', 'token-a', {
            ...set,
            exerciseId: original.exercises[1].id,
            setNumber: 1,
          }),
        )
      ).status,
    ).toBe(409);
    setNow('2026-01-17T12:00:00.000Z');
    expect(
      (
        await handlers.feedback(
          request('POST', 'feedback', 'token-a', { ...checkIn, jointPain: 0 }),
        )
      ).status,
    ).toBe(201);
    const resumed = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    expect(resumed.session).toMatchObject({
      id: original.id,
      week: original.week,
      safetyStop: false,
      exercises: original.exercises,
    });
    expect(resumed.session.loggedSets).toEqual(reopened.session.loggedSets);
    expect((await handlers.revoke(request('DELETE', 'enroll', 'token-a'))).status).toBe(200);
    expect((await handlers.next(request('GET', 'next', 'token-a'))).status).toBe(409);
    expect(
      (await handlers.logSet(request('POST', 'log-set', 'token-a', { ...set, setNumber: 1 })))
        .status,
    ).toBe(409);
  });

  it('reports rejected check-ins as unavailable instead of saved', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const push = records.push.bind(records);
    jest
      .spyOn(records, 'push')
      .mockImplementation(async (subject, collection, rows) =>
        rows.some((row) => row.record_type === 'session_feedback')
          ? { records: [], rejected_ids: rows.map((row) => String(row.id)) }
          : push(subject, collection, rows),
      );
    const response = await handlers.feedback(
      request('POST', 'feedback', 'token-a', {
        sessionId: session.id,
        soreness: 3,
        pump: 1,
        performance: 'stable',
        jointPain: 5,
      }),
    );
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toMatchObject({ error: 'training_unavailable' });
    expect(
      (await records.pull('subject-a', 'training_feedback')).records.filter(
        (row) => row.record_type === 'session_feedback',
      ),
    ).toEqual([]);
  });

  it('allows retry after a rejected completion and reports completion only after acknowledgment', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const update = records.updateTrainingSession.bind(records);
    jest
      .spyOn(records, 'updateTrainingSession')
      .mockImplementation(async (subject, id, revision, setCount, row) =>
        row.status === 'completed' ? null : update(subject, id, revision, setCount, row),
      );
    let lastSet;
    let response;
    for (const exercise of session.exercises) {
      for (let setNumber = 1; setNumber <= exercise.sets; setNumber++) {
        lastSet = {
          sessionId: session.id,
          exerciseId: exercise.id,
          setNumber,
          reps: 10,
          loadKg: 15,
          rir: 3,
        };
        response = await handlers.logSet(request('POST', 'log-set', 'token-a', lastSet));
      }
    }
    expect(response?.status).toBe(503);
    expect((await records.pull('subject-a', 'training_sessions')).records[0].status).toBe(
      'in_progress',
    );
    jest.restoreAllMocks();
    const retry = await handlers.logSet(request('POST', 'log-set', 'token-a', lastSet));
    expect(retry.status).toBe(201);
    await expect(retry.json()).resolves.toMatchObject({ sessionComplete: true });
    expect((await records.pull('subject-a', 'training_sessions')).records[0].status).toBe(
      'completed',
    );
    expect((await records.pull('subject-a', 'logged_sets')).records).toHaveLength(
      session.exercises.reduce(
        (total: number, exercise: { sets: number }) => total + exercise.sets,
        0,
      ),
    );
    // A lost successful response must be retryable after the session has completed.
    const repeated = await handlers.logSet(request('POST', 'log-set', 'token-a', lastSet));
    expect(repeated.status).toBe(201);
    await expect(repeated.json()).resolves.toMatchObject({ sessionComplete: true });
    const changed = await handlers.logSet(
      request('POST', 'log-set', 'token-a', { ...lastSet, reps: 12 }),
    );
    expect(changed.status).toBe(409);
  });

  it.each(['in_progress', 'completed'])(
    'rejects a replay of a deleted %s session without recreating records',
    async (status) => {
      const { handlers, records } = makeHarness();
      await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
      const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
      const sets = session.exercises.flatMap((exercise: { id: string; sets: number }) =>
        Array.from({ length: exercise.sets }, (_, index) => ({
          sessionId: session.id,
          exerciseId: exercise.id,
          setNumber: index + 1,
          reps: 10,
          loadKg: 15,
          rir: 3,
        })),
      );
      for (const set of status === 'completed' ? sets : sets.slice(0, 1)) {
        expect((await handlers.logSet(request('POST', 'log-set', 'token-a', set))).status).toBe(
          201,
        );
      }
      expect((await records.pull('subject-a', 'training_sessions')).records[0].status).toBe(status);
      const originalLogs = (await records.pull('subject-a', 'logged_sets')).records;
      // Revocation can stop after deleting sessions, before removing logs and setup.
      await records.remove('subject-a', 'training_sessions', [session.id]);
      const tombstone = (await records.pull('subject-a', 'training_sessions')).records[0];
      expect(tombstone.deleted_at).not.toBeNull();
      const push = jest.spyOn(records, 'push');
      expect((await handlers.logSet(request('POST', 'log-set', 'token-a', sets[0]))).status).toBe(
        404,
      );
      expect(push).not.toHaveBeenCalled();
      expect((await records.pull('subject-a', 'training_sessions')).records).toEqual([tombstone]);
      expect((await records.pull('subject-a', 'logged_sets')).records).toEqual(originalLogs);
    },
  );

  it('reconciles a saved final set after interruption before reopening the next session', async () => {
    const { handlers, records } = makeHarness();
    await handlers.enroll(request('POST', 'enroll', 'token-a', eligibleSetup));
    const { session } = await (await handlers.next(request('GET', 'next', 'token-a'))).json();
    const update = records.updateTrainingSession.bind(records);
    const reject = jest
      .spyOn(records, 'updateTrainingSession')
      .mockImplementation(async (subject, id, revision, setCount, row) =>
        row.status === 'completed' ? null : update(subject, id, revision, setCount, row),
      );
    for (const exercise of session.exercises) {
      for (let setNumber = 1; setNumber <= exercise.sets; setNumber++) {
        await handlers.logSet(
          request('POST', 'log-set', 'token-a', {
            sessionId: session.id,
            exerciseId: exercise.id,
            setNumber,
            reps: 10,
            loadKg: 15,
            rir: 3,
          }),
        );
      }
    }
    expect((await handlers.next(request('GET', 'next', 'token-a'))).status).toBe(503);
    reject.mockRestore();
    const reopened = await handlers.next(request('GET', 'next', 'token-a'));
    expect(reopened.status).toBe(200);
    const body = await reopened.json();
    expect(body.session.id).not.toBe(session.id);
    expect(body.session.loggedSets).toEqual([]);
    const sessions = (await records.pull('subject-a', 'training_sessions')).records;
    expect(sessions.find((row) => row.id === session.id)?.status).toBe('completed');
    expect(sessions.filter((row) => row.status === 'in_progress')).toHaveLength(1);
  });
});
