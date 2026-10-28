import { TrainingMutationError } from '@/lib/training/mutation-admission';
import { prepareNextBlock } from '@/lib/training/delegated-revisions';
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
import {
  applyWorkoutAction,
  correctTrainingSet,
  logTrainingSet,
  recordTrainingFeedback,
  swapExercise,
} from '@/lib/training/commands';
import {
  getOrCreateNextWorkout,
  loadTrainingRecords,
  pullAllTrainingRecords,
  storeProgramSetup,
} from '@/lib/training/service';
import { MUSCLE_GROUPS, TRAINING_CONSENT_VERSION } from '@/lib/training/types';
import { summarizeTrainingProgress } from '@/lib/training/progress';

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

const FeedbackScoreSchema = z.number().int().min(0).max(10);
const ReadinessSchema = z.enum(['ready', 'limited', 'unknown']);
const MuscleFeedbackSchema = z
  .object({
    soreness: FeedbackScoreSchema.optional(),
    recovery: ReadinessSchema.optional(),
    pump: FeedbackScoreSchema.optional(),
    workload: z.enum(['below_expected', 'as_expected', 'above_expected']).optional(),
    performance: z.enum(['up', 'stable', 'down']).optional(),
  })
  .strict()
  .refine((value) => Object.values(value).some((item) => item !== undefined));

const CorrectSetBodySchema = LogSetBodySchema.extend({
  correctionId: z.string().uuid(),
  expectedRevision: z.number().int().min(0),
}).strict();

const FeedbackBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    soreness: FeedbackScoreSchema.optional(),
    pump: FeedbackScoreSchema.optional(),
    performance: z.enum(['up', 'stable', 'down']).optional(),
    jointPain: FeedbackScoreSchema.optional(),
    muscles: z.partialRecord(z.enum(MUSCLE_GROUPS), MuscleFeedbackSchema).optional(),
    targetMuscle: z.enum(MUSCLE_GROUPS).optional(),
    targetMuscleReadiness: ReadinessSchema.optional(),
    breathingReadiness: ReadinessSchema.optional(),
    generalReadiness: ReadinessSchema.optional(),
    supportingReadiness: z
      .object({
        grip: ReadinessSchema.optional(),
        trunk: ReadinessSchema.optional(),
        muscles: z.partialRecord(z.enum(MUSCLE_GROUPS), ReadinessSchema).optional(),
      })
      .strict()
      .optional(),
    trunkFatigue: FeedbackScoreSchema.optional(),
    generalExhaustion: FeedbackScoreSchema.optional(),
    symptomFlags: z
      .array(z.enum(['pain', 'neurologic', 'other_concerning']))
      .min(1)
      .max(3)
      .optional(),
    symptomNote: z.string().trim().min(1).max(500).optional(),
    originalStatement: z.string().trim().min(1).max(1_000).optional(),
    transcriptionUncertain: z.boolean().optional(),
    interpretations: z
      .array(
        z
          .object({
            claim: z.enum([
              'goal_preference',
              'self_assessed_development',
              'performance',
              'tolerability',
              'symptom',
              'recovery',
              'pump',
              'causal_hypothesis',
              'dose_history',
            ]),
            timeframe: z.enum(['current', 'historical']),
            confidence: z.enum(['low', 'moderate', 'high']),
            corroboratesObservationIds: z
              .array(z.string().trim().min(1).max(160))
              .min(1)
              .max(20)
              .optional(),
            conflictsWithObservationIds: z
              .array(z.string().trim().min(1).max(160))
              .min(1)
              .max(20)
              .optional(),
            proposedExplanation: z.string().trim().min(1).max(500).optional(),
          })
          .strict(),
      )
      .min(1)
      .max(8)
      .optional(),
    source: z.enum(['touch', 'voice', 'text', 'import', 'unknown']).optional(),
    observedAt: z.string().datetime().optional(),
    sourceObservationId: z.string().trim().min(1).max(160).optional(),
    correctsObservationId: z.string().trim().min(1).max(160).optional(),
    context: z
      .object({
        exerciseId: z.string().trim().min(1).max(80).optional(),
        setId: z.string().trim().min(1).max(160).optional(),
        setNumber: z.number().int().min(1).max(50).optional(),
        setOrder: z.number().int().min(1).max(50).optional(),
        reps: z.number().int().min(0).max(100).optional(),
        loadKg: z.number().finite().min(0).max(500).nullable().optional(),
        rir: z.number().int().min(0).max(6).optional(),
        restSeconds: z.number().int().min(0).max(3600).optional(),
        setup: z.string().trim().min(1).max(160).optional(),
        rangeOfMotion: z.enum(['full', 'partial', 'unknown']).optional(),
        setFormat: z.literal('straight').optional(),
      })
      .strict()
      .optional(),
  })
  .strict();

const SwapBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    exerciseId: z.string().trim().min(1).max(64),
    toVariantId: z.string().trim().min(1).max(64).optional(),
    unavailableEquipment: z.array(z.string().trim().min(1).max(32)).max(16).optional(),
    declaredEquipment: z.array(z.string().trim().min(1).max(32)).max(16).optional(),
    excludedConcerns: z.array(z.string().trim().min(1).max(48)).max(16).optional(),
    preferTorsoSupport: z.boolean().optional(),
    maxTrunkDemand: z.enum(['low', 'moderate', 'high']).optional(),
  })
  .strict();

const WorkoutActionBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    eventId: z.string().uuid(),
    expectedRevision: z.number().int().min(0),
    action: z.discriminatedUnion('kind', [
      z
        .object({ kind: z.literal('equipment_unavailable'), exerciseId: z.string().min(1).max(64) })
        .strict(),
      z.object({ kind: z.literal('shorten'), minutes: z.number().int().min(5).max(180) }).strict(),
      z.object({ kind: z.literal('skip'), exerciseId: z.string().min(1).max(64) }).strict(),
      z.object({ kind: z.literal('pain'), exerciseId: z.string().min(1).max(64) }).strict(),
      z.object({ kind: z.literal('pause') }).strict(),
      z.object({ kind: z.literal('resume') }).strict(),
      z.object({ kind: z.literal('end') }).strict(),
    ]),
  })
  .strict();

type RouteDependencies = {
  delegatedEnabled?: () => boolean;
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
    async progress(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      try {
        const snapshot = await loadTrainingRecords(dependencies.records, identity.sub);
        return json(
          withVersion({ progress: summarizeTrainingProgress(snapshot, dependencies.now()) }),
        );
      } catch {
        return apiError('training_unavailable', 503);
      }
    },

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
        if (result.kind === 'block_complete') {
          if (!dependencies.delegatedEnabled?.() || !dependencies.revisions)
            return apiError('training_program_requires_review', 409);
          const next = await prepareNextBlock({
            revisions: dependencies.revisions,
            records: dependencies.records,
            subject: identity.sub,
            now: dependencies.now(),
          });
          if (next.kind !== 'stored') return apiError(next.kind, 409);
          return json(withVersion({ session: null, nextBlock: next.stored }));
        }
        if (result.kind === 'week_complete') {
          return json(
            withVersion({
              session: null,
              week: result.week,
              weekCount: result.weekCount,
              phase: result.phase,
              weeklyFractionalVolume: result.weeklyFractionalVolume,
              decision: result.decision,
            }),
          );
        }
        return json(
          withVersion({
            session: result.session,
            week: result.week,
            weekCount: result.weekCount,
            phase: result.phase,
            weeklyFractionalVolume: result.weeklyFractionalVolume,
            decision: result.decision,
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

    async swap(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      const parsed = SwapBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return apiError('invalid_request', 400);
      try {
        const result = await swapExercise({
          records: dependencies.records,
          subject: identity.sub,
          now: dependencies.now(),
          swap: parsed.data,
        });
        switch (result.kind) {
          case 'swapped':
            return json(
              withVersion({
                swap: result.swap,
                exercise: result.exercise,
                diff: result.diff,
              }),
              201,
            );
          case 'program_not_enrolled':
            return apiError('program_not_enrolled', 409);
          case 'session_not_found':
            return apiError('session_not_found', 404);
          case 'session_not_active':
            return apiError('session_not_active', 409);
          case 'exercise_not_found':
            return apiError('exercise_not_found', 404);
          case 'variant_not_found':
            return apiError('variant_not_found', 404);
          case 'variant_ineligible':
            return json(withVersion({ error: 'variant_ineligible', missing: result.missing }), 409);
          case 'no_feasible_alternative':
            return apiError('no_feasible_alternative', 409);
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
        const now = dependencies.now();
        const result = await recordTrainingFeedback({
          records: dependencies.records,
          subject: identity.sub,
          now,
          createId: dependencies.createId,
          feedback: {
            ...parsed.data,
            source: parsed.data.source ?? 'touch',
            observedAt: parsed.data.observedAt ?? now.toISOString(),
          },
        });
        switch (result.kind) {
          case 'recorded':
            return json(
              withVersion({
                feedback: result.feedback,
                nextSetRecommendation: result.recommendation,
              }),
              201,
            );
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

    async correctSet(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      const parsed = CorrectSetBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return apiError('invalid_request', 400);
      try {
        const result = await correctTrainingSet({
          records: dependencies.records,
          subject: identity.sub,
          now: dependencies.now(),
          set: { ...parsed.data, loadKg: parsed.data.loadKg ?? null },
        });
        switch (result.kind) {
          case 'corrected':
            return json(withVersion({ log: result.log }));
          case 'program_not_enrolled':
            return apiError('program_not_enrolled', 409);
          case 'session_not_found':
            return apiError('session_not_found', 404);
          case 'set_not_found':
            return apiError('set_not_found', 404);
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

    async action(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return apiError('unauthorized', 401);
      if (!featureEnabled()) return apiError('not_found', 404);
      const denied = await allowed(identity.sub);
      if (denied) return denied;
      const parsed = WorkoutActionBodySchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return apiError('invalid_request', 400);
      try {
        const result = await applyWorkoutAction({
          records: dependencies.records,
          subject: identity.sub,
          now: dependencies.now(),
          ...parsed.data,
        });
        switch (result.kind) {
          case 'updated':
            return json(withVersion({ decision: result.decision, session: result.session }));
          case 'program_not_enrolled':
            return apiError('program_not_enrolled', 409);
          case 'session_not_found':
            return apiError('session_not_found', 404);
          case 'session_not_active':
            return apiError('session_not_active', 409);
          case 'stale_revision':
            return apiError('stale_revision', 409);
          case 'stale_current_exercise':
            return apiError('stale_current_exercise', 409);
          case 'no_eligible_substitution':
            return apiError('no_eligible_substitution', 409);
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
