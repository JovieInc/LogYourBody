import type {
  NativeProductRecord,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { logTrainingSet, recordTrainingFeedback } from './commands';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, pullAllTrainingRecords, storeProgramSetup } from './service';
import type { Session } from './types';

const row = (id: string): NativeProductRecord => ({
  id,
  deleted_at: null,
  server_updated_at: '2026-01-01T00:00:00.000Z',
});

describe('training record pagination', () => {
  it('loads every page using the returned update-time cursor', async () => {
    const nextCursor = { since: '2026-01-01T00:00:00.000Z', after_id: 'first' };
    const pages = [
      { records: [row('first')], deleted_ids: [], next_cursor: nextCursor },
      { records: [row('second')], deleted_ids: [], next_cursor: null },
    ];
    const pull = jest.fn(async () => pages.shift()!);
    const records = { pull } as unknown as NativeProductRecordsPort;

    await expect(pullAllTrainingRecords(records, 'subject-a', 'logged_sets')).resolves.toEqual([
      row('first'),
      row('second'),
    ]);
    expect(pull).toHaveBeenCalledTimes(2);
    expect(pull).toHaveBeenNthCalledWith(2, 'subject-a', 'logged_sets', {
      ...nextCursor,
      limit: 500,
    });
  });

  it('fails closed if the record cursor repeats', async () => {
    const nextCursor = { since: '2026-01-01T00:00:00.000Z', after_id: 'first' };
    const pull = jest.fn(async () => ({ records: [], deleted_ids: [], next_cursor: nextCursor }));
    const records = { pull } as unknown as NativeProductRecordsPort;

    await expect(pullAllTrainingRecords(records, 'subject-a', 'training_sessions')).rejects.toThrow(
      'training_records_pagination_stalled',
    );
  });
});

const startedAt = new Date('2026-01-10T12:00:00.000Z');
const followingWeek = new Date('2026-01-17T12:00:00.000Z');

async function enrolledRecords() {
  const records = new MemoryTrainingRecords();
  await storeProgramSetup({
    records,
    subject: 'subject-a',
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'dumbbells',
    },
    now: startedAt,
    createId: () => '11111111-1111-4111-8111-000000000001',
  });
  return records;
}

async function nextWorkout(records: MemoryTrainingRecords, now = startedAt, persist = true) {
  const result = await getOrCreateNextWorkout({ records, subject: 'subject-a', now, persist });
  if (result.kind !== 'workout') throw new Error(`Expected workout, received ${result.kind}`);
  return result;
}

async function logExercises(records: MemoryTrainingRecords, session: Session, all = false) {
  for (const exercise of all ? session.exercises : session.exercises.slice(0, 1)) {
    for (let setNumber = 1; setNumber <= exercise.sets; setNumber += 1) {
      expect(
        await logTrainingSet({
          records,
          subject: 'subject-a',
          now: startedAt,
          set: {
            sessionId: session.id,
            exerciseId: exercise.id,
            setNumber,
            reps: 10,
            loadKg: 25,
            rir: 4,
          },
        }),
      ).toMatchObject({ kind: 'logged' });
    }
  }
}

describe('active training prescription', () => {
  it.each([true, false])(
    'retains targets after partial logging and a week boundary (persist=%s)',
    async (persist) => {
      const records = await enrolledRecords();
      const original = await nextWorkout(records);
      await logExercises(records, original.session);
      const rowsBefore = await records.listAll('subject-a');
      const reopened = await nextWorkout(records, followingWeek, persist);
      expect(reopened.session).toEqual({
        ...original.session,
        loggedSets: expect.arrayContaining([
          expect.objectContaining({
            exerciseId: original.session.exercises[0]?.id,
            setNumber: 1,
            reps: 10,
            loadKg: 25,
            rir: 4,
          }),
          expect.objectContaining({
            exerciseId: original.session.exercises[0]?.id,
            setNumber: 2,
            reps: 10,
            loadKg: 25,
            rir: 4,
          }),
        ]),
      });
      expect(reopened.session.loggedSets).toHaveLength(2);
      expect(reopened.week).toBe(original.week);
      if (!persist) expect(await records.listAll('subject-a')).toEqual(rowsBefore);
      expect(
        (await records.pull('subject-a', 'training_sessions')).records[0]?.prescription,
      ).toEqual({
        ...original.session,
        loggedSets: undefined,
      });
    },
  );

  it.each(['missing', 'wrong-owner-session', 'invalid-target', 'invalid-safety-shape'])(
    'falls back to the existing prescription when the retained snapshot is %s',
    async (invalidKind) => {
      const records = await enrolledRecords();
      const original = await nextWorkout(records);
      await logExercises(records, original.session);
      const stored = (await records.pull('subject-a', 'training_sessions')).records[0]!;
      const { loggedSets: _loggedSets, ...prescription } = original.session;
      const invalidSnapshots: Record<string, unknown> = {
        missing: undefined,
        'wrong-owner-session': { ...prescription, id: 'another-session' },
        'invalid-target': {
          ...prescription,
          exercises: [{ ...prescription.exercises[0], targetReps: 'many' }],
        },
        'invalid-safety-shape': { ...prescription, safetyStop: true },
      };
      await records.push('subject-a', 'training_sessions', [
        { ...stored, initialPrescription: invalidSnapshots[invalidKind] },
      ]);
      const reopened = await nextWorkout(records, followingWeek);
      expect(reopened.session.exercises).toEqual(original.session.exercises);
      expect(
        (await records.pull('subject-a', 'training_sessions')).records[0]?.initialPrescription,
      ).toEqual(prescription);
    },
  );

  it('rejects a malformed effective prescription without writing a replacement', async () => {
    const records = await enrolledRecords();
    await nextWorkout(records);
    const stored = (await records.pull('subject-a', 'training_sessions')).records[0]!;
    await records.push('subject-a', 'training_sessions', [
      { ...stored, prescription: { id: stored.id, exercises: 'invalid' } },
    ]);
    const rowsBefore = await records.listAll('subject-a');
    await expect(nextWorkout(records)).rejects.toThrow('training_session_invalid_prescription');
    expect(await records.listAll('subject-a')).toEqual(rowsBefore);
  });

  it('recovers a legacy paused row from completed history at its original week', async () => {
    const records = await enrolledRecords();
    const original = await nextWorkout(records);
    await logExercises(records, original.session);
    const checkIn = {
      sessionId: original.session.id,
      soreness: 2,
      pump: 5,
      performance: 'stable' as const,
      jointPain: 5,
    };
    await recordTrainingFeedback({
      records,
      subject: 'subject-a',
      now: startedAt,
      createId: () => 'pain',
      feedback: checkIn,
    });
    expect((await nextWorkout(records)).session.safetyStop).toBe(true);
    const stored = (await records.pull('subject-a', 'training_sessions')).records[0]!;
    const { initialPrescription: _initial, ...legacy } = stored;
    await records.push('subject-a', 'training_sessions', [legacy]);
    await recordTrainingFeedback({
      records,
      subject: 'subject-a',
      now: followingWeek,
      createId: () => 'recovered',
      feedback: { ...checkIn, jointPain: 0 },
    });
    const resumed = await nextWorkout(records, followingWeek);
    expect(resumed.session).toMatchObject({
      id: original.session.id,
      week: original.week,
      safetyStop: false,
      exercises: original.session.exercises,
    });
    expect(resumed.session.loggedSets).toHaveLength(2);
  });

  it('keeps current recovery volume changes separate from retained exercise targets', async () => {
    const records = await enrolledRecords();
    const first = await nextWorkout(records);
    await logExercises(records, first.session, true);
    const current = await nextWorkout(records);
    const checkIn = {
      sessionId: first.session.id,
      soreness: 8,
      pump: 5,
      performance: 'down' as const,
      jointPain: 0,
    };
    await recordTrainingFeedback({
      records,
      subject: 'subject-a',
      now: startedAt,
      createId: () => 'prior-decline',
      feedback: checkIn,
    });
    await recordTrainingFeedback({
      records,
      subject: 'subject-a',
      now: startedAt,
      createId: () => 'current-decline',
      feedback: { ...checkIn, sessionId: current.session.id },
    });
    const reduced = await nextWorkout(records);
    expect(reduced.session.exercises).toEqual(
      current.session.exercises.map((exercise) => ({ ...exercise, sets: 1 })),
    );
    const stored = (await records.pull('subject-a', 'training_sessions')).records.find(
      (record) => record.id === current.session.id,
    )!;
    expect(stored.prescription).toMatchObject({ exercises: reduced.session.exercises });
    expect(stored.initialPrescription).toMatchObject({ exercises: current.session.exercises });
    await recordTrainingFeedback({
      records,
      subject: 'subject-a',
      now: startedAt,
      createId: () => 'recovery-update',
      feedback: { ...checkIn, sessionId: current.session.id, performance: 'stable' },
    });
    expect((await nextWorkout(records)).session.exercises).toEqual(current.session.exercises);
  });

  it('progresses a future session from completed history but retains its targets after that history changes', async () => {
    const records = await enrolledRecords();
    const first = await nextWorkout(records);
    await logExercises(records, first.session, true);
    const second = await nextWorkout(records);
    await logExercises(records, second.session, true);
    const future = await nextWorkout(records, followingWeek);
    expect(future.session.id).not.toBe(first.session.id);
    expect(future.session.exercises[0]).toMatchObject({
      targetReps: 11,
      targetLoadKg: 25,
      progression: 'add_reps',
      targetRir: 3,
    });
    const historicalSets = (await records.pull('subject-a', 'logged_sets')).records.filter(
      (log) => log.sessionId === first.session.id,
    );
    await records.push(
      'subject-a',
      'logged_sets',
      historicalSets.map((log) => ({ ...log, reps: 12, loadKg: 30 })),
    );
    const reopened = await nextWorkout(records, followingWeek);
    expect(reopened.session).toEqual(future.session);
  });
});
