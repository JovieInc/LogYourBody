/** Actual recovery service + record adapter against the verifier's socket-only
 * PostgreSQL16. Only Neon transport is replaced; no production endpoint is used. */
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { promisify } from 'node:util';
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonNativeProductRecords } from '../../src/lib/neon/native-product-records-adapter';
import { buildSession, createMesoBlock } from '../../src/lib/training/engine';
import {
  createRecoveryTrial,
  decideRecoveryTrial,
  readRecovery,
} from '../../src/lib/training/recovery-records';
import { getOrCreateNextWorkout } from '../../src/lib/training/service';
import type { TrainingProgramSetup } from '../../src/lib/training/types';

const execute = promisify(execFile);
const client: string[] = JSON.parse(process.argv[2]);
assert(
  client.includes('-h') && client[client.indexOf('-h') + 1].startsWith('/tmp/lyb-mutation-pg-'),
);
const quote = (value: unknown) =>
  value === null ? 'null' : "'" + String(value).replaceAll("'", "''") + "'";
async function sql(statement: string) {
  return (
    await execute(client[0], [...client.slice(1), '-c', statement], { timeout: 30_000 })
  ).stdout.trim();
}
const database = {
  query: async (statement: string, params: unknown[]) => {
    const bound = statement.replace(/\$(\d+)/g, (_, index: string) =>
      quote(params[Number(index) - 1]),
    );
    return JSON.parse(
      await sql(
        `select coalesce(json_agg(row_to_json(recovery_row)), '[]'::json) from (${bound}) recovery_row;`,
      ),
    );
  },
} as unknown as NeonQueryFunction<false, false>;

async function main() {
  const subject = 'recovery-' + randomUUID();
  const startedAt = '2026-10-12T09:00:00.000Z';
  const now = new Date('2026-10-13T10:00:00.000Z');
  const setup: TrainingProgramSetup = {
    id: randomUUID(),
    startedAt,
    consentVersion: 'hypertrophy-coach-v1',
    adultConfirmed: true,
    safetyConfirmed: true,
    equipment: 'dumbbells',
    sessionsPerWeek: 3,
  };
  const target = {
    muscle: 'shoulders',
    exerciseId: 'dumbbell_lateral_raise',
    goal: 'emphasize',
  } as const;
  const records = createNeonNativeProductRecords(database);
  const base = { records, subject, now };
  await sql(
    `insert into app_users(id,identity_provider,identity_subject,profile_data) values(${quote(randomUUID())},'jovie',${quote(subject)},'{"date_of_birth":"1990-01-01"}');`,
  );
  async function seed(collection: string, payload: Record<string, unknown>) {
    await sql(
      `insert into native_records(collection,id,user_subject,payload) values(${quote(collection)},${quote(payload.id)}::uuid,${quote(subject)},${quote(JSON.stringify(payload))}::jsonb);`,
    );
  }
  await seed('training_feedback', { ...setup, record_type: 'program_setup' });
  async function completed(at: string, reps: number, limited: boolean, sets = 2) {
    const session = buildSession({
      setup,
      block: createMesoBlock(startedAt, at),
      sessionId: randomUUID(),
      slot: 0,
      logs: [],
      feedback: [],
    });
    session.exercises.find((item) => item.id === target.exerciseId)!.sets = sets;
    await seed('training_sessions', {
      id: session.id,
      record_type: 'workout_session',
      programSetupId: setup.id,
      blockId: 'block-1',
      weekNumber: 1,
      slot: 0,
      status: 'completed',
      prescription: session,
    });
    for (let setNumber = 1; setNumber <= sets; setNumber++) {
      await seed('logged_sets', {
        id: randomUUID(),
        record_type: 'set_log',
        sessionId: session.id,
        exerciseId: target.exerciseId,
        setNumber,
        reps: reps - setNumber + 1,
        loadKg: 10,
        rir: 3,
        completedAt: at,
      });
    }
    await seed('training_feedback', {
      id: randomUUID(),
      record_type: 'session_feedback',
      sessionId: session.id,
      createdAt: at,
      muscles: {
        shoulders: {
          performance: limited ? 'down' : 'stable',
          recovery: limited ? 'limited' : 'ready',
          soreness: 2,
        },
      },
      jointPain: 0,
      generalReadiness: 'ready',
      supportingReadiness: { trunk: 'ready', grip: 'ready' },
      context: {
        exerciseId: target.exerciseId,
        setNumber: 1,
        setup: 'same',
        restSeconds: 120,
        setOrder: 1,
        rangeOfMotion: 'full',
        setFormat: 'straight',
      },
    });
  }
  await completed(startedAt, 12, false);
  await completed('2026-10-13T09:00:00.000Z', 8, true);
  async function next(at = now, persist = false) {
    return getOrCreateNextWorkout({ ...base, now: at, persist, recoveryEnabled: true });
  }
  function sets(result: Awaited<ReturnType<typeof next>>) {
    assert.equal(result.kind, 'workout');
    if (result.kind !== 'workout') throw new Error('expected workout');
    return result.session.exercises.find((item) => item.id === target.exerciseId)!.sets;
  }
  assert.equal(sets(await next()), 2);
  const trial = await createRecoveryTrial({ ...base, target, requestId: randomUUID() });
  assert.equal(trial.inference.action, 'reduce');
  assert.equal(sets(await next()), 2);
  const decide = (
    decision: 'apply' | 'reject' | 'revert' | 'review',
    expectedRevision: number,
    at = now,
    trialId = trial.id,
  ) => decideRecoveryTrial({ ...base, now: at, decision, expectedRevision, trialId });
  await decide('apply', 0);
  assert.equal(sets(await next()), 1);
  assert.equal((await readRecovery({ ...base, target })).trials[0].state, 'applied');
  const pending = await createRecoveryTrial({ ...base, target, requestId: randomUUID() });
  const wednesday = new Date('2026-10-14T10:00:00.000Z');
  await completed('2026-10-14T09:00:00.000Z', 10, false, 1);
  const reviewed = await decide('review', 1, wednesday);
  assert.equal(reviewed.outcome.decision, 'retain');
  assert.equal(reviewed.state, 'applied');
  assert.deepEqual(reviewed.baseline, trial.baseline);
  await decide('revert', 2, wednesday);
  const followingWeek = new Date('2026-10-19T09:00:00.000Z');
  assert.equal(sets(await next(followingWeek)), 2);
  await assert.rejects(() => decide('apply', 0, wednesday, pending.id), /trial_context_changed/);
  const rejected = await decide('reject', 0, wednesday, pending.id);
  assert.equal(rejected.state, 'rejected');
  assert.equal(sets(await next(followingWeek, true)), 2);
  assert.equal(sets(await next(followingWeek)), 2);
  const replay = await readRecovery({ ...base, now: wednesday, target });
  assert.deepEqual(
    replay.trials.find((item) => item.id === trial.id)!.history.map((entry) => entry.state),
    ['proposed', 'applied', 'applied', 'reverted'],
  );
  console.log(
    'PASS recovery actual adapter: Monday dose -> Tuesday decline -> reviewed reduction -> comparable response -> retain -> revert -> persisted replay; stale apply and rejection preserve prior plan',
  );
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
