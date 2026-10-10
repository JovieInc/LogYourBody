import { logTrainingSet, recordTrainingFeedback } from './commands';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, stableTrainingUuid, storeProgramSetup } from './service';
import type { Session } from './types';

const subject = 'privacy-owner';
const now = new Date('2026-01-10T12:00:00.000Z');
function barrier() {
  let enter!: () => void;
  let release!: () => void;
  return {
    entered: new Promise<void>((r) => {
      enter = r;
    }),
    released: new Promise<void>((r) => {
      release = r;
    }),
    enter: () => enter(),
    release: () => release(),
  };
}
async function fixture() {
  const records = new MemoryTrainingRecords();
  await storeProgramSetup({
    records,
    subject,
    now,
    createId: () => '11111111-1111-4111-8111-000000000001',
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'dumbbells',
    },
  });
  return records;
}
async function workout(records: MemoryTrainingRecords) {
  const result = await getOrCreateNextWorkout({ records, subject, now });
  if (result.kind !== 'workout') throw new Error('fixture');
  return result.session;
}
async function revoke(records: MemoryTrainingRecords) {
  for (const collection of ['training_sessions', 'logged_sets', 'training_feedback'] as const) {
    const { records: rows } = await records.pull(subject, collection);
    await records.remove(
      subject,
      collection,
      rows.map((r) => r.id),
    );
  }
}
async function live(records: MemoryTrainingRecords) {
  const all = await records.listAll(subject);
  return [...all.training_sessions, ...all.logged_sets, ...all.training_feedback];
}
function setInput(session: Session, exercise = session.exercises[0]!, setNumber = 1) {
  return {
    sessionId: session.id,
    exerciseId: exercise.id,
    setNumber,
    reps: exercise.targetReps,
    loadKg: exercise.targetLoadKg,
    rir: exercise.targetRir,
  };
}

describe('training mutation privacy admission', () => {
  it.each(['new session', 'existing session', 'feedback', 'new set', 'completion'] as const)(
    '%s cannot write after revoke returns',
    async (kind) => {
      const records = await fixture();
      const session = kind === 'new session' ? null : await workout(records);
      let finalSet = session ? setInput(session) : null;
      if (kind === 'completion' && session) {
        const pairs = session.exercises.flatMap((e) =>
          Array.from({ length: e.sets }, (_, n) => setInput(session, e, n + 1)),
        );
        finalSet = pairs.pop()!;
        for (const set of pairs)
          await records.insertTrainingSet(subject, {
            ...set,
            id: stableTrainingUuid(subject, session.id, set.exerciseId, String(set.setNumber)),
            record_type: 'set_log',
            completedAt: now.toISOString(),
          });
      }
      const held = barrier();
      const commit = records.trainingMutations.commit.bind(records.trainingMutations);
      records.trainingMutations.commit = async (input) => {
        if (kind !== 'completion' || input.action === 'session_update') {
          held.enter();
          await held.released;
        }
        return commit(input);
      };
      const operation =
        kind === 'feedback'
          ? recordTrainingFeedback({
              records,
              subject,
              now,
              createId: () => '22222222-2222-4222-8222-000000000001',
              feedback: {
                sessionId: session!.id,
                soreness: 2,
                pump: 2,
                performance: 'stable',
                jointPain: 0,
              },
            })
          : kind === 'new set' || kind === 'completion'
            ? logTrainingSet({ records, subject, now, set: finalSet! })
            : getOrCreateNextWorkout({ records, subject, now });
      await held.entered;
      await revoke(records);
      expect(await live(records)).toEqual([]);
      held.release();
      await operation.catch(() => undefined);
      expect(await live(records)).toEqual([]);
    },
  );
});

describe('training immutable request admission', () => {
  it.each(['revoke', 'same-owner generation', 'recreated owner'] as const)(
    'identical feedback cannot acknowledge an old snapshot after %s',
    async (change) => {
      const records = await fixture();
      const session = await workout(records);
      const input = {
        records,
        subject,
        now,
        createId: () => '22222222-2222-4222-8222-000000000001',
        feedback: {
          sessionId: session.id,
          soreness: 2,
          pump: 2,
          performance: 'stable' as const,
          jointPain: 0,
        },
      };
      await recordTrainingFeedback(input);
      const original = await records.listAll(subject);
      const before = await records.trainingMutations.captureAdmission(subject);
      const held = barrier();
      const pull = records.pull.bind(records);
      let first = true;
      records.pull = async (...args) => {
        const snapshot = await pull(...args);
        if (first && args[1] === 'training_feedback') {
          first = false;
          held.enter();
          await held.released;
        }
        return snapshot;
      };
      const operation = recordTrainingFeedback(input);
      await held.entered;
      if (change === 'revoke') {
        await revoke(records);
      } else {
        if (change === 'recreated owner') {
          await records.deleteAllForSubject(subject);
          records.recreateOwner(subject);
        }
        for (const collection of ['training_feedback', 'training_sessions', 'logged_sets'] as const)
          await records.push(subject, collection, original[collection]);
      }
      const after = await records.trainingMutations.captureAdmission(subject);
      if (change === 'revoke') expect(after).toBeNull();
      else if (change === 'same-owner generation') {
        expect(after!.ownerId).toBe(before!.ownerId);
        expect(after!.generation).toBeGreaterThan(before!.generation);
      } else {
        expect(after!.ownerId).not.toBe(before!.ownerId);
        expect(after!.generation).toBe(before!.generation);
        expect(after!.setupId).toBe(before!.setupId);
      }
      const replacement = await records.listAll(subject);
      const rejection = expect(operation).rejects.toMatchObject({
        code: 'training_context_changed',
      });
      held.release();
      await rejection;
      expect(await records.listAll(subject)).toEqual(replacement);
    },
  );

  it('acknowledges current identical feedback without inserting or changing its timestamp', async () => {
    const records = await fixture();
    const session = await workout(records);
    const input = {
      records,
      subject,
      now,
      createId: jest.fn(() => '22222222-2222-4222-8222-000000000001'),
      feedback: {
        sessionId: session.id,
        soreness: 2,
        pump: 2,
        performance: 'stable' as const,
        jointPain: 0,
      },
    };
    const first = await recordTrainingFeedback(input);
    const rows = await records.listAll(subject);
    const commit = jest.spyOn(records.trainingMutations, 'commit');
    input.createId.mockClear();
    const replay = await recordTrainingFeedback({
      ...input,
      now: new Date(now.getTime() + 60_000),
    });
    expect(replay).toEqual(first);
    expect(commit).not.toHaveBeenCalled();
    expect(input.createId).not.toHaveBeenCalled();
    expect(await records.listAll(subject)).toEqual(rows);
  });

  it.each(['next', 'set', 'feedback'] as const)(
    '%s captures incarnation before snapshot awaits',
    async (kind) => {
      const records = await fixture();
      const session = await workout(records);
      const original = await records.listAll(subject);
      const before = await records.trainingMutations.captureAdmission(subject);
      const held = barrier();
      const pull = records.pull.bind(records);
      let first = true;
      records.pull = async (...args) => {
        if (first) {
          first = false;
          held.enter();
          await held.released;
        }
        return pull(...args);
      };
      const operation =
        kind === 'next'
          ? getOrCreateNextWorkout({ records, subject, now })
          : kind === 'set'
            ? logTrainingSet({ records, subject, now, set: setInput(session) })
            : recordTrainingFeedback({
                records,
                subject,
                now,
                createId: () => '22222222-2222-4222-8222-000000000001',
                feedback: {
                  sessionId: session.id,
                  soreness: 2,
                  pump: 2,
                  performance: 'stable',
                  jointPain: 0,
                },
              });
      await held.entered;
      await records.deleteAllForSubject(subject);
      records.recreateOwner(subject);
      for (const collection of ['training_feedback', 'training_sessions', 'logged_sets'] as const)
        await records.push(subject, collection, original[collection]);
      const after = await records.trainingMutations.captureAdmission(subject);
      expect(after).toMatchObject({
        generation: before!.generation,
        setupId: before!.setupId,
        revisionId: before!.revisionId,
      });
      expect(after!.ownerId).not.toBe(before!.ownerId);
      const replacement = await records.listAll(subject);
      const rejection = expect(operation).rejects.toMatchObject({
        code: 'training_context_changed',
      });
      held.release();
      await rejection;
      expect(await records.listAll(subject)).toEqual(replacement);
    },
  );

  it('fails closed without an atomic capability before reading or writing records', async () => {
    const records = await fixture();
    const port = Object.create(records) as MemoryTrainingRecords;
    Object.defineProperty(port, 'trainingMutations', { value: undefined });
    const pull = jest.spyOn(records, 'pull');
    const push = jest.spyOn(records, 'push');
    await expect(getOrCreateNextWorkout({ records: port, subject, now })).rejects.toMatchObject({
      code: 'training_mutations_unavailable',
    });
    expect(pull).not.toHaveBeenCalled();
    expect(push).not.toHaveBeenCalled();
  });
});
