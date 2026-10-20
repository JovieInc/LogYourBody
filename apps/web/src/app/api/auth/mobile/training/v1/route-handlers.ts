import { TrainingMutationError } from '@/lib/training/mutation-admission';
import type { TrainingRevisionsPort } from '@/lib/ports/training-revisions';
import { profileConfirmsAdult } from '@/lib/training/eligibility';
import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { UserDirectoryPort } from '@/lib/ports/user-directory';
import {
  isTrainingRecordCollection,
  type NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { logTrainingSet, recordTrainingFeedback } from '@/lib/training/commands';
import {
  getOrCreateNextWorkout,
  pullAllTrainingRecords,
  storeProgramSetup,
} from '@/lib/training/service';
import { TRAINING_CONSENT_VERSION } from '@/lib/training/types';

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
  revisions?: TrainingRevisionsPort;
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
      } catch (error) {
        if (error instanceof TrainingMutationError && error.code === 'training_context_changed')
          return apiError(error.code, 409);
        return apiError('training_unavailable', 503);
      }
    },

    async enroll(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      // Capture before body/profile/rate-limit awaits: a request already in flight
      // cannot restore consent after a concurrent revoke or canonical input edit.
      let enrollmentContext;
      try {
        enrollmentContext = await dependencies.revisions?.readContext(identity.sub);
        if (dependencies.revisions && !enrollmentContext)
          return apiError('training_unavailable', 503);
      } catch {
        return apiError('training_unavailable', 503);
      }
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
          revisions: dependencies.revisions,
          expectedContext: enrollmentContext ?? undefined,
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
        if (dependencies.revisions) {
          const deleted = await dependencies.revisions.revoke(identity.sub);
          return json(withVersion({ revoked: true, deletedRecords: deleted }));
        }
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
        const result = await logTrainingSet({
          records: dependencies.records,
          subject: identity.sub,
          now: dependencies.now(),
          set: { ...parsed.data, loadKg: parsed.data.loadKg ?? null },
        });
        switch (result.kind) {
          case 'logged':
            return json(
              withVersion({ log: result.log, sessionComplete: result.sessionComplete }),
              201,
            );
          case 'program_not_enrolled':
            return apiError('program_not_enrolled', 409);
          case 'session_not_found':
            return apiError('session_not_found', 404);
          case 'session_not_active':
            return apiError('session_not_active', 409);
          case 'set_not_in_session':
            return apiError('set_not_in_session', 400);
          case 'set_conflict':
            return apiError('set_conflict', 409);
          case 'rejected':
            return apiError('training_unavailable', 503);
        }
      } catch (error) {
        if (error instanceof TrainingMutationError && error.code === 'training_context_changed')
          return apiError(error.code, 409);
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
        const result = await recordTrainingFeedback({
          records: dependencies.records,
          subject: identity.sub,
          now: dependencies.now(),
          createId: dependencies.createId,
          feedback: parsed.data,
        });
        switch (result.kind) {
          case 'recorded':
            return json(withVersion({ feedback: result.feedback }), 201);
          case 'program_not_enrolled':
            return apiError('program_not_enrolled', 409);
          case 'session_not_found':
            return apiError('session_not_found', 404);
          case 'invalid':
            return apiError('invalid_request', 400);
          case 'rejected':
            return apiError('training_unavailable', 503);
        }
      } catch (error) {
        if (error instanceof TrainingMutationError && error.code === 'training_context_changed')
          return apiError(error.code, 409);
        return apiError('training_unavailable', 503);
      }
    },
  };
}
