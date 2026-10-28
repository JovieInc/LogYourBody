import { captureTrainingAdmission } from '@/lib/training/mutation-admission';
import { z } from 'zod';
import type { TrainingRevisionsPort } from '@/lib/ports/training-revisions';
import {
  createDelegatedProposal,
  decideDelegatedProposal,
} from '@/lib/training/delegated-revisions';
import { steeringRequestSchema } from '@/lib/training/delegation-contract';
import { decideProposalInputSchema } from '@/lib/training/revision-contract';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import { EXERCISE_CATALOG } from '@/lib/training/catalog';
import {
  applyWorkoutAction,
  correctTrainingSet,
  logTrainingSet,
  recordTrainingFeedback,
  swapExercise,
} from '@/lib/training/commands';
import { summarizeTrainingProgress } from '@/lib/training/progress';
import {
  getOrCreateNextWorkout,
  loadTrainingRecords,
  type NextWorkoutResult,
} from '@/lib/training/service';
import {
  MUSCLE_GROUPS,
  type ExercisePrescription,
  type Session,
  type SetLog,
} from '@/lib/training/types';
import { poundsToKg } from '@/lib/voice/intent-parser';
import { LYB_MCP_SCOPES, type LybMcpScope } from './contract';

export type McpToolDependencies = {
  revisions?: TrainingRevisionsPort;
  delegatedEnabled?: () => boolean;
  records: NativeProductRecordsPort;
  now: () => Date;
  createId: () => string;
};

export type McpToolResult = {
  content: Array<{ type: 'text'; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};

type ToolDefinition = {
  delegated?: boolean;
  name: string;
  title: string;
  description: string;
  scope: LybMcpScope;
  readOnly: boolean;
  input: z.ZodType<Record<string, unknown>>;
  inputSchema: Record<string, unknown>;
  run(subject: string, args: never, deps: McpToolDependencies): Promise<McpToolResult>;
};

const ENROLL_IN_APP =
  'Training is not set up for this account yet. Open the LogYourBody iPhone app and start the hypertrophy plan from Today, then try again.';

const kgToPounds = (kg: number) => Math.round((kg / 0.45359237) * 10) / 10;

function text(message: string, structuredContent?: Record<string, unknown>): McpToolResult {
  return { content: [{ type: 'text', text: message }], structuredContent };
}

function failure(message: string): McpToolResult {
  return { content: [{ type: 'text', text: message }], isError: true };
}

function normalizeName(value: string): string {
  return value
    .toLocaleLowerCase('en-US')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function matchExercise(
  session: Session,
  spoken: string,
):
  | { kind: 'match'; exercise: ExercisePrescription }
  | { kind: 'none' | 'ambiguous'; options: string[] } {
  const options = session.exercises.map((exercise) => exercise.name);
  const byId = session.exercises.find((exercise) => exercise.id === spoken);
  if (byId) return { kind: 'match', exercise: byId };
  const wanted = normalizeName(spoken);
  if (!wanted) return { kind: 'none', options };
  const exact = session.exercises.filter((exercise) => normalizeName(exercise.name) === wanted);
  if (exact.length === 1) return { kind: 'match', exercise: exact[0]! };
  const words = wanted.split(' ');
  const partial = session.exercises.filter((exercise) => {
    const name = normalizeName(exercise.name);
    return name.includes(wanted) || words.every((word) => name.split(' ').includes(word));
  });
  if (partial.length === 1) return { kind: 'match', exercise: partial[0]! };
  return { kind: partial.length > 1 ? 'ambiguous' : 'none', options };
}

function describeExercise(exercise: ExercisePrescription, logs: SetLog[]) {
  const logged = logs
    .filter((log) => log.exerciseId === exercise.id)
    .sort((a, b) => a.setNumber - b.setNumber)
    .map(({ setNumber, reps, loadKg, rir }) => ({
      setNumber,
      reps,
      loadKg,
      loadLb: loadKg === null ? null : kgToPounds(loadKg),
      rir,
    }));
  return {
    id: exercise.id,
    name: exercise.name,
    sets: exercise.sets,
    targetReps: exercise.targetReps,
    repRange: exercise.repRange,
    targetRir: exercise.targetRir,
    targetLoadKg: exercise.targetLoadKg,
    targetLoadLb: exercise.targetLoadKg === null ? null : kgToPounds(exercise.targetLoadKg),
    loadInstruction: exercise.loadInstruction,
    loggedSets: logged,
  };
}

function workoutPayload(result: Extract<NextWorkoutResult, { kind: 'workout' }>, logs: SetLog[]) {
  const sessionLogs = logs.filter((log) => log.sessionId === result.session.id);
  return {
    status: 'workout',
    week: result.week,
    weekCount: result.weekCount,
    session: {
      id: result.session.id,
      title: result.session.title,
      safetyStop: result.session.safetyStop,
      explanation: result.session.explanation,
      exercises: result.session.exercises.map((exercise) =>
        describeExercise(exercise, sessionLogs),
      ),
    },
  };
}

function summarizeWorkout(payload: ReturnType<typeof workoutPayload>): string {
  const { session } = payload;
  if (session.safetyStop) {
    return `${session.explanation ?? 'Training is paused after a pain report.'} No sets are planned for this session.`;
  }
  const lines = session.exercises.map((exercise) => {
    const load =
      exercise.targetLoadKg === null
        ? exercise.loadInstruction
          ? ` (${exercise.loadInstruction})`
          : ''
        : ` at ${exercise.targetLoadKg} kg (${exercise.targetLoadLb} lb)`;
    const done = exercise.loggedSets.length ? `, ${exercise.loggedSets.length} logged` : '';
    return `- ${exercise.name}: ${exercise.sets} sets of ${exercise.targetReps} reps, ${exercise.targetRir} reps in reserve${load}${done}`;
  });
  return [`Week ${payload.week} of ${payload.weekCount}, ${session.title}.`, ...lines].join('\n');
}

const emptyInput = z.object({}).strict();

const logSetsInput = z
  .object({
    exercise: z.string().trim().min(1).max(80),
    weightUnit: z.enum(['kg', 'lb']).default('kg'),
    sets: z
      .array(
        z
          .object({
            reps: z.number().int().min(1).max(50),
            rir: z.number().int().min(0).max(6),
            load: z.number().finite().min(0).max(1100).nullable().optional(),
            setNumber: z.number().int().min(1).max(10).optional(),
          })
          .strict(),
      )
      .min(1)
      .max(10),
  })
  .strict();

const feedbackScore = z.number().int().min(0).max(10);
const feedbackReadiness = z.enum(['ready', 'limited', 'unknown']);
const muscleFeedbackInput = z
  .object({
    soreness: feedbackScore.optional(),
    recovery: feedbackReadiness.optional(),
    pump: feedbackScore.optional(),
    workload: z.enum(['below_expected', 'as_expected', 'above_expected']).optional(),
    performance: z.enum(['up', 'stable', 'down']).optional(),
  })
  .strict()
  .refine((value) => Object.values(value).some((item) => item !== undefined));

const feedbackInput = z
  .object({
    soreness: feedbackScore.optional(),
    pump: feedbackScore.optional(),
    performance: z.enum(['up', 'stable', 'down']).optional(),
    jointPain: feedbackScore.optional(),
    muscles: z.partialRecord(z.enum(MUSCLE_GROUPS), muscleFeedbackInput).optional(),
    targetMuscle: z.enum(MUSCLE_GROUPS).optional(),
    targetMuscleReadiness: feedbackReadiness.optional(),
    breathingReadiness: feedbackReadiness.optional(),
    generalReadiness: feedbackReadiness.optional(),
    supportingReadiness: z
      .object({
        grip: feedbackReadiness.optional(),
        trunk: feedbackReadiness.optional(),
        muscles: z.partialRecord(z.enum(MUSCLE_GROUPS), feedbackReadiness).optional(),
      })
      .strict()
      .optional(),
    trunkFatigue: feedbackScore.optional(),
    generalExhaustion: feedbackScore.optional(),
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
    source: z.enum(['voice', 'text', 'import']).optional(),
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

const workoutControlInput = z
  .object({
    action: z.enum(['equipment_unavailable', 'shorten', 'skip', 'pain', 'pause', 'resume', 'end']),
    minutes: z.number().int().min(5).max(180).optional(),
  })
  .strict()
  .refine((value) => value.action !== 'shorten' || value.minutes !== undefined, {
    message: 'minutes is required when shortening a workout',
  });

const correctSetInput = z
  .object({
    exercise: z.string().trim().min(1).max(80),
    setNumber: z.number().int().min(1).max(10),
    reps: z.number().int().min(1).max(50),
    rir: z.number().int().min(0).max(6),
    load: z.number().finite().min(0).max(1100).nullable().optional(),
    weightUnit: z.enum(['kg', 'lb']).default('kg'),
  })
  .strict();

const progressInput = z.object({ exercise: z.string().trim().min(1).max(80).optional() }).strict();

const swapInput = z
  .object({
    exercise: z.string().trim().min(1).max(80),
    variant: z.string().trim().min(1).max(80).optional(),
    unavailableEquipment: z.array(z.string().trim().min(1).max(32)).max(16).optional(),
    preferTorsoSupport: z.boolean().optional(),
  })
  .strict();

const score = (description: string) => ({ type: 'integer', minimum: 0, maximum: 10, description });
const planRevisionInput = z
  .object({
    action: z.enum(['read', 'propose', 'decide']),
    proposal: steeringRequestSchema.optional(),
    decision: decideProposalInputSchema.optional(),
  })
  .strict();

export const LYB_MCP_TOOLS: ToolDefinition[] = [
  {
    name: 'revise_training_program',
    title: 'Review or revise the training program',
    description:
      'Read the canonical plan and generation, propose typed or natural-language steering, or explicitly apply/reject a reviewed proposal. LYB builds prescriptions. Proposing is never applying. Repeat the persisted proposal diff and receipt; never claim a change from conversational text.',
    delegated: true,
    scope: LYB_MCP_SCOPES.trainingWrite,
    readOnly: false,
    input: planRevisionInput,
    inputSchema: z.toJSONSchema(planRevisionInput),
    async run(subject, raw: z.infer<typeof planRevisionInput>, deps) {
      if (!deps.delegatedEnabled?.() || !deps.revisions)
        return failure('Delegated programming is unavailable.');
      if (raw.action === 'read') {
        const context = await deps.revisions.readContext(subject);
        return text('Current saved program. Propose a change before applying it.', {
          generation: context?.generation,
          headRevision: context?.headRevision,
          setups: context?.legacySetups,
        });
      }
      const input = {
        records: deps.records,
        revisions: deps.revisions,
        subject,
        actor: { kind: 'user' as const, subject },
        now: deps.now(),
      };
      const result =
        raw.action === 'propose'
          ? await createDelegatedProposal({ ...input, body: raw.proposal })
          : await decideDelegatedProposal({ ...input, body: raw.decision });
      if (result.kind === 'stored')
        return text('Review this saved proposal. It has not been applied.', { ...result });
      if (result.kind === 'decided')
        return text(`Revision ${result.receipt.status}.`, { ...result });
      if (result.kind === 'question') return text(result.question, { ...result });
      return failure(`Plan change was not applied: ${result.kind}.`);
    },
  },
  {
    name: 'get_todays_workout',
    title: "Get today's workout",
    description:
      "Shows the user's next LogYourBody hypertrophy session: each exercise with planned sets, target reps, reps in reserve, the suggested load when one is known, and sets already logged. Read-only. Numbers come from the LogYourBody training engine; repeat them as given.",
    scope: LYB_MCP_SCOPES.trainingRead,
    readOnly: true,
    input: emptyInput,
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    async run(subject, _args, deps) {
      const result = await getOrCreateNextWorkout({
        records: deps.records,
        subject,
        now: deps.now(),
        persist: false,
      });
      if (result.kind === 'not_enrolled') return text(ENROLL_IN_APP, { status: 'not_enrolled' });
      if (result.kind === 'week_complete') {
        return text(
          `All sessions for week ${result.week} are done. The next session unlocks next week.`,
          {
            status: 'week_complete',
            week: result.week,
          },
        );
      }
      if (result.kind === 'block_complete')
        return text('Your block is complete. Review the recommended next block in LogYourBody.', {
          status: 'block_complete',
        });
      const snapshot = await loadTrainingRecords(deps.records, subject);
      const payload = workoutPayload(result, snapshot.logs);
      return text(summarizeWorkout(payload), payload);
    },
  },
  {
    name: 'log_sets',
    title: 'Log sets',
    description:
      "Adds completed sets for one exercise in the user's current LogYourBody session, for example \"bench press, 2 sets of 10 at 185 lb, 2 reps in reserve\". Starts today's session if needed. Only adds new sets: sets already logged and sets beyond today's plan are skipped and reported. Exercise names can be spoken naturally.",
    scope: LYB_MCP_SCOPES.trainingWrite,
    readOnly: false,
    input: logSetsInput,
    inputSchema: {
      type: 'object',
      properties: {
        exercise: {
          type: 'string',
          description: 'Exercise name as the user said it, or its id from get_todays_workout.',
        },
        weightUnit: {
          type: 'string',
          enum: ['kg', 'lb'],
          default: 'kg',
          description: 'Unit the user used for load.',
        },
        sets: {
          type: 'array',
          minItems: 1,
          maxItems: 10,
          items: {
            type: 'object',
            properties: {
              reps: { type: 'integer', minimum: 1, maximum: 50 },
              rir: {
                type: 'integer',
                minimum: 0,
                maximum: 6,
                description: 'Reps in reserve the user reported.',
              },
              load: {
                type: ['number', 'null'],
                minimum: 0,
                description: 'Load in weightUnit; null or omitted for bodyweight.',
              },
              setNumber: {
                type: 'integer',
                minimum: 1,
                maximum: 10,
                description: 'Only when the user names the set.',
              },
            },
            required: ['reps', 'rir'],
            additionalProperties: false,
          },
        },
      },
      required: ['exercise', 'sets'],
      additionalProperties: false,
    },
    async run(subject, args: z.infer<typeof logSetsInput>, deps) {
      const admission = await captureTrainingAdmission(deps.records, subject);
      if (!admission) return failure(ENROLL_IN_APP);
      const now = deps.now();
      // Preview first so a misheard exercise never starts a session.
      const workout = await getOrCreateNextWorkout({
        records: deps.records,
        subject,
        now,
        persist: false,
        admission,
      });
      if (workout.kind === 'not_enrolled') return failure(ENROLL_IN_APP);
      if (workout.kind === 'week_complete' || workout.kind === 'block_complete')
        return failure(
          'The current training period is complete. Review the next plan before logging more work.',
        );
      if (workout.session.safetyStop)
        return failure(workout.session.explanation ?? 'Training is paused after a pain report.');
      const match = matchExercise(workout.session, args.exercise);
      if (match.kind !== 'match') {
        return failure(
          `${match.kind === 'ambiguous' ? 'That matches more than one exercise' : "That exercise is not in today's session"}. Today's exercises: ${match.options.join(', ')}.`,
        );
      }
      const { exercise } = match;
      await getOrCreateNextWorkout({ records: deps.records, subject, now, admission });
      const snapshot = await loadTrainingRecords(deps.records, subject);
      const taken = new Set(
        snapshot.logs
          .filter((log) => log.sessionId === workout.session.id && log.exerciseId === exercise.id)
          .map((log) => log.setNumber),
      );
      const logged: Array<{ setNumber: number; reps: number; loadKg: number | null; rir: number }> =
        [];
      const skipped: Array<{ setNumber: number | null; reason: string }> = [];
      let sessionComplete = false;
      for (const set of args.sets) {
        const setNumber =
          set.setNumber ??
          Array.from({ length: exercise.sets }, (_, index) => index + 1).find((n) => !taken.has(n));
        if (setNumber === undefined || setNumber > exercise.sets) {
          skipped.push({
            setNumber: setNumber ?? null,
            reason: `today's plan has ${exercise.sets} sets`,
          });
          continue;
        }
        if (taken.has(setNumber)) {
          skipped.push({ setNumber, reason: 'already logged' });
          continue;
        }
        const loadKg =
          set.load === undefined || set.load === null
            ? null
            : args.weightUnit === 'lb'
              ? poundsToKg(set.load)
              : set.load;
        if (loadKg !== null && loadKg > 500) {
          skipped.push({ setNumber, reason: 'load is outside the 0 to 500 kg range' });
          continue;
        }
        const result = await logTrainingSet({
          admission,
          records: deps.records,
          subject,
          now,
          set: {
            sessionId: workout.session.id,
            exerciseId: exercise.id,
            setNumber,
            reps: set.reps,
            loadKg,
            rir: set.rir,
          },
        });
        if (result.kind !== 'logged') {
          skipped.push({ setNumber, reason: result.kind.replace(/_/g, ' ') });
          continue;
        }
        taken.add(setNumber);
        sessionComplete = result.sessionComplete;
        logged.push({ setNumber, reps: set.reps, loadKg, rir: set.rir });
      }
      const summary = [
        logged.length
          ? `Logged ${logged.length} ${logged.length === 1 ? 'set' : 'sets'} of ${exercise.name}.`
          : `No new sets of ${exercise.name} were logged.`,
        ...skipped.map((item) => `Set ${item.setNumber ?? 'extra'} skipped: ${item.reason}.`),
        sessionComplete
          ? "That completes today's session. Ask how it felt to record a check-in."
          : '',
      ]
        .filter(Boolean)
        .join(' ');
      const payload = {
        exercise: { id: exercise.id, name: exercise.name, plannedSets: exercise.sets },
        logged: logged.map((item) => ({
          ...item,
          loadLb: item.loadKg === null ? null : kgToPounds(item.loadKg),
        })),
        skipped,
        sessionComplete,
      };
      return logged.length ? text(summary, payload) : { ...text(summary, payload), isError: true };
    },
  },
  {
    name: 'control_workout',
    title: 'Control active workout',
    description:
      'Applies one situational action to the active workout. Equipment conflicts are evaluated by the training engine, which reorders before using an eligible substitution. Skip and time limits apply only to this session. Pain always enters the safety pause path.',
    scope: LYB_MCP_SCOPES.trainingWrite,
    readOnly: false,
    input: workoutControlInput,
    inputSchema: {
      type: 'object',
      properties: {
        action: {
          type: 'string',
          enum: ['equipment_unavailable', 'shorten', 'skip', 'pain', 'pause', 'resume', 'end'],
        },
        minutes: { type: 'integer', minimum: 5, maximum: 180 },
      },
      required: ['action'],
      additionalProperties: false,
    },
    async run(subject, args: z.infer<typeof workoutControlInput>, deps) {
      const workout = await getOrCreateNextWorkout({
        records: deps.records,
        subject,
        now: deps.now(),
      });
      if (workout.kind === 'not_enrolled') return failure(ENROLL_IN_APP);
      if (workout.kind === 'week_complete' || workout.kind === 'block_complete')
        return failure('There is no active workout to update.');
      const logs = workout.session.loggedSets;
      const current = workout.session.exercises.find((exercise) =>
        Array.from({ length: exercise.sets }, (_, index) => index + 1).some(
          (setNumber) =>
            !logs.some((log) => log.exerciseId === exercise.id && log.setNumber === setNumber),
        ),
      );
      const needsExercise = ['equipment_unavailable', 'skip', 'pain'].includes(args.action);
      if (needsExercise && !current) return failure('There is no current exercise to update.');
      const action =
        args.action === 'equipment_unavailable'
          ? { kind: args.action, exerciseId: current!.id }
          : args.action === 'skip' || args.action === 'pain'
            ? { kind: args.action, exerciseId: current!.id }
            : args.action === 'shorten'
              ? { kind: args.action, minutes: args.minutes! }
              : { kind: args.action };
      const result = await applyWorkoutAction({
        records: deps.records,
        subject,
        now: deps.now(),
        sessionId: workout.session.id,
        eventId: deps.createId(),
        expectedRevision: workout.session.executionRevision ?? 0,
        action,
      });
      if (result.kind !== 'updated') return failure(`Workout unchanged: ${result.kind}.`);
      return text(`Workout updated: ${result.decision}.`, {
        sessionId: result.session.id,
        decision: result.decision,
        revision: result.session.executionRevision,
      });
    },
  },
  {
    name: 'correct_set',
    title: 'Correct a logged set',
    description:
      'Corrects one already-logged set in the active workout while preserving its stable identity and an audit trail. Use only when the user explicitly corrects prior values.',
    scope: LYB_MCP_SCOPES.trainingWrite,
    readOnly: false,
    input: correctSetInput,
    inputSchema: {
      type: 'object',
      properties: {
        exercise: { type: 'string' },
        setNumber: { type: 'integer', minimum: 1, maximum: 10 },
        reps: { type: 'integer', minimum: 1, maximum: 50 },
        rir: { type: 'integer', minimum: 0, maximum: 6 },
        load: { type: ['number', 'null'], minimum: 0 },
        weightUnit: { type: 'string', enum: ['kg', 'lb'], default: 'kg' },
      },
      required: ['exercise', 'setNumber', 'reps', 'rir'],
      additionalProperties: false,
    },
    async run(subject, args: z.infer<typeof correctSetInput>, deps) {
      const workout = await getOrCreateNextWorkout({
        records: deps.records,
        subject,
        now: deps.now(),
      });
      if (workout.kind !== 'workout') return failure('There is no active workout to correct.');
      const match = matchExercise(workout.session, args.exercise);
      if (match.kind !== 'match') return failure("That exercise is not in today's active workout.");
      const prior = workout.session.loggedSets.find(
        (log) => log.exerciseId === match.exercise.id && log.setNumber === args.setNumber,
      );
      if (!prior) return failure('That set has not been logged, so there is nothing to correct.');
      const loadKg =
        args.load === undefined
          ? prior.loadKg
          : args.load === null
            ? null
            : args.weightUnit === 'lb'
              ? poundsToKg(args.load)
              : args.load;
      const result = await correctTrainingSet({
        records: deps.records,
        subject,
        now: deps.now(),
        set: {
          sessionId: workout.session.id,
          exerciseId: match.exercise.id,
          setNumber: args.setNumber,
          reps: args.reps,
          loadKg,
          rir: args.rir,
          correctionId: deps.createId(),
          expectedRevision: prior.revision ?? 0,
        },
      });
      if (result.kind !== 'corrected') return failure(`Set unchanged: ${result.kind}.`);
      return text(`Corrected ${match.exercise.name}, set ${args.setNumber}.`, {
        sessionId: workout.session.id,
        exerciseId: match.exercise.id,
        setNumber: args.setNumber,
        reps: args.reps,
        loadKg,
        rir: args.rir,
      });
    },
  },
  {
    name: 'log_session_feedback',
    title: 'Log session check-in',
    description:
      'Adds only the observations the user provided for their most recent LogYourBody session or current set. It supports optional per-muscle soreness, recovery, pump, workload and performance plus distinct target, breathing, general, grip/trunk and symptom signals. Missing values stay unknown; never guess or turn a timer into clearance.',
    scope: LYB_MCP_SCOPES.trainingWrite,
    readOnly: false,
    input: feedbackInput,
    inputSchema: {
      type: 'object',
      properties: {
        soreness: score('How sore the trained muscles feel, 0 none to 10 severe.'),
        pump: score('Muscle pump during the session, 0 none to 10 extreme.'),
        performance: {
          type: 'string',
          enum: ['up', 'stable', 'down'],
          description: 'Performance versus last time.',
        },
        jointPain: score('Joint pain, 0 none to 10 severe.'),
        muscles: {
          type: 'object',
          description:
            'Optional observations keyed by muscle; include only muscles the user described.',
          properties: Object.fromEntries(
            MUSCLE_GROUPS.map((muscle) => [
              muscle,
              {
                type: 'object',
                properties: {
                  soreness: score('Reported soreness for this muscle.'),
                  recovery: { type: 'string', enum: ['ready', 'limited', 'unknown'] },
                  pump: score('Reported pump for this muscle.'),
                  workload: {
                    type: 'string',
                    enum: ['below_expected', 'as_expected', 'above_expected'],
                  },
                  performance: { type: 'string', enum: ['up', 'stable', 'down'] },
                },
                additionalProperties: false,
                minProperties: 1,
              },
            ]),
          ),
          additionalProperties: false,
          minProperties: 1,
        },
        targetMuscle: { type: 'string', enum: [...MUSCLE_GROUPS] },
        targetMuscleReadiness: { type: 'string', enum: ['ready', 'limited', 'unknown'] },
        breathingReadiness: { type: 'string', enum: ['ready', 'limited', 'unknown'] },
        generalReadiness: { type: 'string', enum: ['ready', 'limited', 'unknown'] },
        supportingReadiness: {
          type: 'object',
          properties: {
            grip: { type: 'string', enum: ['ready', 'limited', 'unknown'] },
            trunk: { type: 'string', enum: ['ready', 'limited', 'unknown'] },
            muscles: {
              type: 'object',
              properties: Object.fromEntries(
                MUSCLE_GROUPS.map((muscle) => [
                  muscle,
                  { type: 'string', enum: ['ready', 'limited', 'unknown'] },
                ]),
              ),
              additionalProperties: false,
              minProperties: 1,
            },
          },
          additionalProperties: false,
          minProperties: 1,
        },
        trunkFatigue: score('Non-pain trunk or back fatigue, 0 none to 10 extreme.'),
        generalExhaustion: score('General exhaustion, 0 none to 10 extreme.'),
        symptomFlags: {
          type: 'array',
          items: { type: 'string', enum: ['pain', 'neurologic', 'other_concerning'] },
          minItems: 1,
          maxItems: 3,
        },
        symptomNote: { type: 'string', maxLength: 500 },
        originalStatement: {
          type: 'string',
          maxLength: 1000,
          description: 'The user’s original wording. Preserve uncertain transcription as heard.',
        },
        transcriptionUncertain: { type: 'boolean' },
        interpretations: {
          type: 'array',
          minItems: 1,
          maxItems: 8,
          description:
            'Claim-specific interpretations. Confidence belongs to each claim, never to the user globally.',
          items: {
            type: 'object',
            properties: {
              claim: {
                type: 'string',
                enum: [
                  'goal_preference',
                  'self_assessed_development',
                  'performance',
                  'tolerability',
                  'symptom',
                  'recovery',
                  'pump',
                  'causal_hypothesis',
                  'dose_history',
                ],
              },
              timeframe: { type: 'string', enum: ['current', 'historical'] },
              confidence: { type: 'string', enum: ['low', 'moderate', 'high'] },
              corroboratesObservationIds: {
                type: 'array',
                items: { type: 'string', maxLength: 160 },
                minItems: 1,
                maxItems: 20,
              },
              conflictsWithObservationIds: {
                type: 'array',
                items: { type: 'string', maxLength: 160 },
                minItems: 1,
                maxItems: 20,
              },
              proposedExplanation: { type: 'string', maxLength: 500 },
            },
            required: ['claim', 'timeframe', 'confidence'],
            additionalProperties: false,
          },
        },
        source: { type: 'string', enum: ['voice', 'text', 'import'] },
        observedAt: { type: 'string', format: 'date-time' },
        sourceObservationId: { type: 'string', maxLength: 160 },
        correctsObservationId: { type: 'string', maxLength: 160 },
        context: {
          type: 'object',
          properties: {
            exerciseId: { type: 'string', maxLength: 80 },
            setId: { type: 'string', maxLength: 160 },
            setNumber: { type: 'integer', minimum: 1, maximum: 50 },
            setOrder: { type: 'integer', minimum: 1, maximum: 50 },
            reps: { type: 'integer', minimum: 0, maximum: 100 },
            loadKg: { type: ['number', 'null'], minimum: 0, maximum: 500 },
            rir: { type: 'integer', minimum: 0, maximum: 6 },
            restSeconds: { type: 'integer', minimum: 0, maximum: 3600 },
            setup: { type: 'string', maxLength: 160 },
            rangeOfMotion: { type: 'string', enum: ['full', 'partial', 'unknown'] },
            setFormat: { type: 'string', enum: ['straight'] },
          },
          additionalProperties: false,
        },
      },
      minProperties: 1,
      additionalProperties: false,
    },
    async run(subject, args: z.infer<typeof feedbackInput>, deps) {
      const admission = await captureTrainingAdmission(deps.records, subject);
      if (!admission) return failure(ENROLL_IN_APP);
      const snapshot = await loadTrainingRecords(deps.records, subject);
      if (!snapshot.setup) return failure(ENROLL_IN_APP);
      const latest = snapshot.sessions
        .filter(
          (record) => (record as { programSetupId?: string }).programSetupId === snapshot.setup?.id,
        )
        .sort(
          (a, b) =>
            Date.parse(String((b as { startedAt?: string }).startedAt ?? b.server_updated_at)) -
            Date.parse(String((a as { startedAt?: string }).startedAt ?? a.server_updated_at)),
        )[0];
      if (!latest) return failure('There is no session to check in on yet. Log a workout first.');
      const now = deps.now();
      const result = await recordTrainingFeedback({
        admission,
        records: deps.records,
        subject,
        now,
        createId: deps.createId,
        feedback: {
          sessionId: latest.id,
          ...args,
          source: args.source ?? 'text',
          observedAt: args.observedAt ?? now.toISOString(),
        },
      });
      if (result.kind !== 'recorded')
        return failure('That check-in could not be saved. Try again.');
      const pain =
        (args.jointPain ?? 0) >= 4 || args.symptomFlags?.length
          ? ' A pain or concerning symptom report pauses the affected work and follows the existing safety pathway. If it persists or worsens, check with a qualified clinician.'
          : '';
      return text(`Check-in saved.${pain}`, {
        sessionId: latest.id,
        ...args,
        nextSetRecommendation: result.recommendation,
      });
    },
  },
  {
    name: 'swap_exercise',
    title: 'Swap an exercise',
    description:
      "Replaces one movement in the user's current LogYourBody session with a reviewed catalog variant that trains the same primary muscle and is feasible with the equipment available. The swap holds for the rest of the training block; the new variant keeps its own progression history. Ask the user before swapping, and pass unavailableEquipment only for what is unavailable today.",
    scope: LYB_MCP_SCOPES.trainingWrite,
    readOnly: false,
    input: swapInput,
    inputSchema: {
      type: 'object',
      properties: {
        exercise: {
          type: 'string',
          description: 'Exercise to replace, as the user said it or by id.',
        },
        variant: {
          type: 'string',
          description:
            'Optional catalog variant to swap to (name or id). Omit to pick the closest feasible option.',
        },
        unavailableEquipment: {
          type: 'array',
          items: { type: 'string' },
          description: 'Equipment unavailable for this session only, e.g. ["bench"]. Never stored.',
        },
        preferTorsoSupport: {
          type: 'boolean',
          description: 'Rank torso-supported variants first (e.g. low back discomfort).',
        },
      },
      required: ['exercise'],
      additionalProperties: false,
    },
    async run(subject, args: z.infer<typeof swapInput>, deps) {
      const admission = await captureTrainingAdmission(deps.records, subject);
      if (!admission) return failure(ENROLL_IN_APP);
      const now = deps.now();
      const workout = await getOrCreateNextWorkout({
        records: deps.records,
        subject,
        now,
        persist: false,
        admission,
      });
      if (workout.kind === 'not_enrolled') return failure(ENROLL_IN_APP);
      if (workout.kind === 'week_complete' || workout.kind === 'block_complete')
        return failure(
          'The current training period is complete. Review the next plan before logging more work.',
        );
      if (workout.session.safetyStop)
        return failure(workout.session.explanation ?? 'Training is paused after a pain report.');
      const match = matchExercise(workout.session, args.exercise);
      if (match.kind !== 'match') {
        return failure(
          `${match.kind === 'ambiguous' ? 'That matches more than one exercise' : "That exercise is not in today's session"}. Today's exercises: ${match.options.join(', ')}.`,
        );
      }
      await getOrCreateNextWorkout({ records: deps.records, subject, now, admission });
      let toVariantId: string | undefined;
      if (args.variant) {
        const wanted = normalizeName(args.variant);
        const pool = EXERCISE_CATALOG.filter(
          (variant) =>
            variant.primaryMuscle === match.exercise.primaryMuscle &&
            variant.id !== match.exercise.id,
        );
        const picked = pool.filter(
          (variant) => variant.id === args.variant || normalizeName(variant.name) === wanted,
        );
        if (picked.length === 0) {
          return failure(
            `There is no reviewed ${match.exercise.primaryMuscle} variant by that name. Options: ${pool.map((variant) => variant.name).join(', ') || 'none'}.`,
          );
        }
        toVariantId = picked[0]!.id;
      }
      const result = await swapExercise({
        records: deps.records,
        subject,
        now,
        admission,
        swap: {
          sessionId: workout.session.id,
          exerciseId: match.exercise.id,
          toVariantId,
          unavailableEquipment: args.unavailableEquipment,
          preferTorsoSupport: args.preferTorsoSupport,
        },
      });
      switch (result.kind) {
        case 'swapped': {
          const message = [
            `Swapped ${match.exercise.name} for ${result.exercise.name}.`,
            `Plan unchanged: ${result.exercise.sets} sets of ${result.exercise.targetReps} reps at ${result.exercise.targetRir} reps in reserve. It stays swapped for the rest of this block.`,
            `Changes: ${result.diff.join('; ')}.`,
          ].join(' ');
          return text(message, {
            sessionId: workout.session.id,
            swap: { from: match.exercise.id, to: result.exercise.id },
            exercise: result.exercise,
            diff: result.diff,
          });
        }
        case 'variant_not_found':
          return failure('That variant is not in the reviewed catalog for this muscle.');
        case 'variant_ineligible':
          return failure(
            `That variant needs equipment that is not available: ${result.missing.join(', ') || 'a required item'}.`,
          );
        case 'no_feasible_alternative':
          return failure(
            'No feasible alternative trains the same muscle with the equipment available.',
          );
        case 'session_not_active':
          return failure('That session is no longer active.');
        case 'exercise_not_found':
        case 'session_not_found':
          return failure('That exercise is not in the current session.');
        default:
          return failure('The swap could not be saved. Try again.');
      }
    },
  },
  {
    name: 'get_training_progress',
    title: 'Get training progress',
    description:
      "Summarizes what the user has logged in LogYourBody: completed sessions, sets in the last 7 days, and for each exercise the last session's sets and heaviest set. Optionally filter to one exercise. Read-only; it reports history and never prescribes.",
    scope: LYB_MCP_SCOPES.trainingRead,
    readOnly: true,
    input: progressInput,
    inputSchema: {
      type: 'object',
      properties: {
        exercise: { type: 'string', description: 'Optional exercise name to focus on.' },
      },
      additionalProperties: false,
    },
    async run(subject, args: z.infer<typeof progressInput>, deps) {
      const snapshot = await loadTrainingRecords(deps.records, subject);
      const progress = summarizeTrainingProgress(snapshot, deps.now());
      if (!progress.enrolled) return text(ENROLL_IN_APP, { enrolled: false });
      const wanted = args.exercise ? normalizeName(args.exercise) : null;
      const exercises = wanted
        ? progress.exercises.filter(
            (item) =>
              normalizeName(item.name).includes(wanted) || item.exerciseId === args.exercise,
          )
        : progress.exercises;
      const lines = exercises.slice(0, 12).map((item) => {
        const heaviest = item.heaviestSet
          ? `, heaviest ${item.heaviestSet.loadKg} kg (${kgToPounds(item.heaviestSet.loadKg!)} lb) for ${item.heaviestSet.reps}`
          : '';
        const last = item.lastSession
          .map((set) => `${set.reps}${set.loadKg === null ? '' : ` x ${set.loadKg} kg`}`)
          .join(', ');
        return `- ${item.name}: last time ${last}${heaviest}`;
      });
      const header = `${progress.completedSessions} sessions completed, ${progress.setsLast7Days} sets in the last 7 days.`;
      return text([header, ...(lines.length ? lines : ['No sets logged yet.'])].join('\n'), {
        ...progress,
        exercises,
      });
    },
  },
];

export function listTools(delegatedEnabled = false) {
  return LYB_MCP_TOOLS.filter((tool) => !tool.delegated || delegatedEnabled).map((tool) => {
    const securitySchemes = [{ type: 'oauth2', scopes: [tool.scope] }];
    return {
      name: tool.name,
      title: tool.title,
      description: tool.description,
      inputSchema: tool.inputSchema,
      annotations: {
        title: tool.title,
        readOnlyHint: tool.readOnly,
        destructiveHint: false,
        openWorldHint: false,
        idempotentHint: tool.readOnly,
      },
      securitySchemes,
      _meta: { securitySchemes },
    };
  });
}

export function findTool(name: unknown): ToolDefinition | undefined {
  return LYB_MCP_TOOLS.find((tool) => tool.name === name);
}
