import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { UserDirectoryPort } from '@/lib/ports/user-directory';
import {
  isTrainingRecordCollection,
  type NativeProductRecord,
  type NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { validTrainingFeedback, validateSetLog } from '@/lib/training/engine';
import {
  getOrCreateNextWorkout,
  isWorkoutSessionRecord,
  loadTrainingRecords,
  pullAllTrainingRecords,
  stableTrainingUuid,
  storeProgramSetup,
} from '@/lib/training/service';
import { TRAINING_CONSENT_VERSION, type SetLog, type TrainingFeedback } from '@/lib/training/types';

export const TRAINING_API_VERSION = 1;

const EnrollBodySchema = z
  .object({
    adultConfirmed: z.boolean(),
    safetyConfirmed: z.boolean(),
    sessionsPerWeek: z.union([z.literal(2), z.literal(3)]),
    equipment: z.enum(['dumbbells', 'full_gym']),
  })
  .strict();

const LogSetBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    exerciseId: z.string().trim().min(1).max(64),
    setNumber: z.number().int().min(1).max(10),
    reps: z.number().int().min(1).max(50),
    loadKg: z.number().finite().min(0).max(500).nullable().optional(),
    rir: z.number().int().min(0).max(6),
  })
  .strict();

const FeedbackBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    soreness: z.number().int().min(0).max(10),
    pump: z.number().int().min(0).max(10),
    performance: z.enum(['up', 'stable', 'down']),
    jointPain: z.number().int().min(0).max(10),
  })
  .strict();

type RouteDependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  records: NativeProductRecordsPort;
  users: UserDirectoryPort;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  createId: () => string;
  now: () => Date;
  enabled: () => boolean;
};

function json(payload: unknown, status = 200) {
  return NextResponse.json(payload, { status, headers: { 'Cache-Control': 'no-store' } });
}

function apiError(error: string, status: number) {
  return json({ version: TRAINING_API_VERSION, error }, status);
}

function rateLimitError(result: Extract<ChatRateLimitResult, { allowed: false }>) {
  return NextResponse.json(
    { version: TRAINING_API_VERSION, error: 'rate_limited' },
    {
      status: 429,
      headers: { 'Cache-Control': 'no-store', 'Retry-After': String(result.retryAfterSeconds) },
    },
  );
}

function withVersion(payload: Record<string, unknown>) {
  return { version: TRAINING_API_VERSION, ...payload };
}

function profileConfirmsAdult(dateOfBirth: unknown, today: Date): boolean {
  if (typeof dateOfBirth !== 'string') return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateOfBirth.slice(0, 10));
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  )
    return false;
  let age = today.getUTCFullYear() - year;
  const birthdayPassed =
    today.getUTCMonth() + 1 > month ||
    (today.getUTCMonth() + 1 === month && today.getUTCDate() >= day);
  if (!birthdayPassed) age -= 1;
  return age >= 18;
}

async function collectionRecords(
  records: NativeProductRecordsPort,
  subject: string,
  collection: 'training_sessions' | 'logged_sets' | 'training_feedback',
) {
  return { records: await pullAllTrainingRecords(records, subject, collection) };
}

export function createTrainingRouteHandlers(dependencies: RouteDependencies) {
  async function authorized(request: NextRequest) {
    return dependencies.authenticate(request);
  }

  async function allowed(subject: string) {
    const result = await dependencies.reserveRequest(subject);
    return result.allowed ? null : rateLimitError(result);
  }

  function featureEnabled() {
    return dependencies.enabled();
  }

  return {
    async next(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      try {
        const result = await getOrCreateNextWorkout({
          records: dependencies.records,
          subject: identity.sub,
          now: dependencies.now(),
        });
        if (result.kind === 'not_enrolled')
          return json(withVersion({ error: 'program_not_enrolled' }), 409);
        if (result.kind === 'week_complete') {
          return json(
            withVersion({
              session: null,
              week: result.week,
              weeklyFractionalVolume: result.weeklyFractionalVolume,
            }),
          );
        }
        return json(
          withVersion({
            session: result.session,
            week: result.week,
            weekCount: result.weekCount,
            weeklyFractionalVolume: result.weeklyFractionalVolume,
          }),
        );
      } catch {
        return apiError('training_unavailable', 503);
      }
    },

    async enroll(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      const parsed = EnrollBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return apiError('invalid_request', 400);
      if (!parsed.data.adultConfirmed || !parsed.data.safetyConfirmed)
        return apiError('eligibility_not_confirmed', 403);
      try {
        const user = await dependencies.users.getUser(identity.sub);
        if (!profileConfirmsAdult(user?.profileData.date_of_birth, dependencies.now())) {
          return apiError('adult_profile_required', 403);
        }
        const setup = await storeProgramSetup({
          records: dependencies.records,
          subject: identity.sub,
          setup: {
            adultConfirmed: true,
            safetyConfirmed: true,
            sessionsPerWeek: parsed.data.sessionsPerWeek,
            equipment: parsed.data.equipment,
          },
          now: dependencies.now(),
          createId: dependencies.createId,
        });
        return json(
          withVersion({
            program: {
              id: setup.id,
              consentVersion: TRAINING_CONSENT_VERSION,
              sessionsPerWeek: setup.sessionsPerWeek,
              equipment: setup.equipment,
            },
          }),
          201,
        );
      } catch {
        return apiError('training_unavailable', 503);
      }
    },

    async revoke(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      try {
        const [sessions, sets, feedback] = await Promise.all([
          collectionRecords(dependencies.records, identity.sub, 'training_sessions'),
          collectionRecords(dependencies.records, identity.sub, 'logged_sets'),
          collectionRecords(dependencies.records, identity.sub, 'training_feedback'),
        ]);
        const groups = [
          ['training_sessions', sessions.records],
          ['logged_sets', sets.records],
          ['training_feedback', feedback.records],
        ] as const;
        let deleted = 0;
        for (const [collection, rows] of groups) {
          if (!isTrainingRecordCollection(collection)) continue;
          const ids = rows.filter((row) => row.deleted_at === null).map((row) => row.id);
          if (ids.length)
            deleted += (await dependencies.records.remove(identity.sub, collection, ids))
              .deleted_ids.length;
        }
        return json(withVersion({ revoked: true, deletedRecords: deleted }));
      } catch {
        return apiError('training_unavailable', 503);
      }
    },

    async logSet(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      const parsed = LogSetBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return apiError('invalid_request', 400);
      try {
        const [snapshot, sessions] = await Promise.all([
          loadTrainingRecords(dependencies.records, identity.sub),
          collectionRecords(dependencies.records, identity.sub, 'training_sessions'),
        ]);
        if (!snapshot.setup) return apiError('program_not_enrolled', 409);
        const sessionRecord = sessions.records.find(
          (record) => record.id === parsed.data.sessionId,
        );
        if (
          !sessionRecord ||
          !isWorkoutSessionRecord(sessionRecord) ||
          sessionRecord.programSetupId !== snapshot.setup.id
        ) {
          return apiError('session_not_found', 404);
        }
        if (sessionRecord.status !== 'in_progress') return apiError('session_not_active', 409);
        const session = sessionRecord.prescription;
        if (
          !session ||
          !validateSetLog(
            {
              id: 'server-generated',
              ...parsed.data,
              loadKg: parsed.data.loadKg ?? null,
              completedAt: dependencies.now().toISOString(),
            },
            session,
          )
        )
          return apiError('set_not_in_session', 400);

        const completedAt = dependencies.now().toISOString();
        const logId = stableTrainingUuid(
          identity.sub,
          session.id,
          parsed.data.exerciseId,
          String(parsed.data.setNumber),
        );
        const log: SetLog & { record_type: string } = {
          id: logId,
          record_type: 'set_log',
          sessionId: session.id,
          exerciseId: parsed.data.exerciseId,
          setNumber: parsed.data.setNumber,
          reps: parsed.data.reps,
          loadKg: parsed.data.loadKg ?? null,
          rir: parsed.data.rir,
          completedAt,
        };
        const saved = await dependencies.records.push(identity.sub, 'logged_sets', [log]);
        if (saved.rejected_ids.includes(logId)) return apiError('training_unavailable', 503);
        const allLogs = [...snapshot.logs, log];
        const sessionComplete = session.exercises.every((exercise) =>
          Array.from({ length: exercise.sets }, (_, index) => index + 1).every((setNumber) =>
            allLogs.some(
              (record) =>
                record.sessionId === session.id &&
                record.exerciseId === exercise.id &&
                record.setNumber === setNumber,
            ),
          ),
        );
        if (sessionComplete) {
          await dependencies.records.push(identity.sub, 'training_sessions', [
            {
              ...sessionRecord,
              status: 'completed',
              completedAt,
            },
          ]);
        }
        return json(withVersion({ log: saved.records[0] ?? log, sessionComplete }), 201);
      } catch {
        return apiError('training_unavailable', 503);
      }
    },

    async feedback(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      const parsed = FeedbackBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return apiError('invalid_request', 400);
      try {
        const snapshot = await loadTrainingRecords(dependencies.records, identity.sub);
        if (!snapshot.setup) return apiError('program_not_enrolled', 409);
        const sessionExists = snapshot.sessions.some(
          (record) =>
            record.id === parsed.data.sessionId &&
            (record as NativeProductRecord & { programSetupId?: string }).programSetupId ===
              snapshot.setup?.id,
        );
        if (!sessionExists) return apiError('session_not_found', 404);
        const latestFeedbackTime = snapshot.feedback.reduce(
          (latest, item) => Math.max(latest, Date.parse(item.createdAt)),
          0,
        );
        const createdAt = new Date(
          Math.max(dependencies.now().getTime(), latestFeedbackTime + 1),
        ).toISOString();
        const feedback: TrainingFeedback & { record_type: string } = {
          id: dependencies.createId(),
          record_type: 'session_feedback',
          ...parsed.data,
          createdAt,
        };
        if (!validTrainingFeedback(feedback)) return apiError('invalid_request', 400);
        await dependencies.records.push(identity.sub, 'training_feedback', [feedback]);
        return json(withVersion({ feedback }), 201);
      } catch {
        return apiError('training_unavailable', 503);
      }
    },
  };
}
