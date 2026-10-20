import { captureTrainingAdmission } from '@/lib/training/mutation-admission';
import { z } from 'zod';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import { logTrainingSet, recordTrainingFeedback } from '@/lib/training/commands';
import { summarizeTrainingProgress } from '@/lib/training/progress';
import {
  getOrCreateNextWorkout,
  loadTrainingRecords,
  type NextWorkoutResult,
} from '@/lib/training/service';
import type { ExercisePrescription, Session, SetLog } from '@/lib/training/types';
import { poundsToKg } from '@/lib/voice/intent-parser';
import { LYB_MCP_SCOPES, type LybMcpScope } from './contract';

export type McpToolDependencies = {
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

const feedbackInput = z
  .object({
    soreness: z.number().int().min(0).max(10),
    pump: z.number().int().min(0).max(10),
    performance: z.enum(['up', 'stable', 'down']),
    jointPain: z.number().int().min(0).max(10),
  })
  .strict();

const progressInput = z.object({ exercise: z.string().trim().min(1).max(80).optional() }).strict();

const score = (description: string) => ({ type: 'integer', minimum: 0, maximum: 10, description });

export const LYB_MCP_TOOLS: ToolDefinition[] = [
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
      if (workout.kind === 'week_complete')
        return failure(`All sessions for week ${workout.week} are already complete.`);
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
    name: 'log_session_feedback',
    title: 'Log session check-in',
    description:
      "Adds the user's check-in for their most recent LogYourBody session: soreness, pump and joint pain from 0 to 10, and whether performance went up, stayed stable or went down. The training engine uses it to adjust or pause the next session. Ask the user for each value; never guess.",
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
      },
      required: ['soreness', 'pump', 'performance', 'jointPain'],
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
      const result = await recordTrainingFeedback({
        admission,
        records: deps.records,
        subject,
        now: deps.now(),
        createId: deps.createId,
        feedback: { sessionId: latest.id, ...args },
      });
      if (result.kind !== 'recorded')
        return failure('That check-in could not be saved. Try again.');
      const pain =
        args.jointPain >= 4
          ? ' Joint pain at that level pauses the affected work. If it persists or worsens, check with a qualified clinician.'
          : '';
      return text(`Check-in saved.${pain}`, { sessionId: latest.id, ...args });
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

export function listTools() {
  return LYB_MCP_TOOLS.map((tool) => {
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
