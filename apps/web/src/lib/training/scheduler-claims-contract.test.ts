/** @jest-environment node */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import ts from 'typescript';
import { SCHEDULER_CLAIMS, schedulerClaim } from './scheduler-claims';
import { nextEligibleSession, type RollingProgram } from './rolling-session';
import { reviewRollingSchedule, type RollingScheduleReview } from './rolling-schedule';
import { history, reduction, source } from './rolling-schedule.testing';
import { planSessionDuration, type SessionDurationInput } from './session-duration';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';
import { applyWorkoutAction } from './workout-actions';
import { buildSession, createMesoBlock } from './engine';
import { TRAINING_CONSENT_VERSION } from './types';

function parsed(name: string): ts.SourceFile {
  return ts.createSourceFile(
    name,
    readFileSync(join(__dirname, name), 'utf8'),
    ts.ScriptTarget.Latest,
    true,
  );
}

/** Read code values, never string literals from conditions, comments or prose.
 * An unfamiliar emission form fails closed so the contract must be extended. */
function codesIn(node: ts.Node): string[] {
  if (ts.isStringLiteral(node)) return [node.text];
  if (ts.isLiteralTypeNode(node)) return codesIn(node.literal);
  if (ts.isUnionTypeNode(node)) return node.types.flatMap(codesIn);
  if (ts.isArrayLiteralExpression(node)) return node.elements.flatMap(codesIn);
  if (ts.isSpreadElement(node) || ts.isParenthesizedExpression(node))
    return codesIn(node.expression);
  if (ts.isConditionalExpression(node))
    return [...codesIn(node.whenTrue), ...codesIn(node.whenFalse)];
  // The queue's shorthand property is governed by its reason union below.
  if (ts.isIdentifier(node) && node.text === 'reason') return [];
  throw new Error(`Unrecognized scheduler code expression: ${node.getText()}`);
}

function emittedCodes(file: string): string[] {
  const codes: string[] = [];
  function visit(node: ts.Node) {
    if (ts.isTypeAliasDeclaration(node) && /Reason$/.test(node.name.text)) {
      codes.push(...codesIn(node.type));
    }
    if (ts.isVariableDeclaration(node) && node.name.getText() === 'reason' && node.initializer) {
      codes.push(...codesIn(node.initializer));
    }
    if (
      ts.isBinaryExpression(node) &&
      node.left.getText() === 'reason' &&
      node.operatorToken.kind === ts.SyntaxKind.EqualsToken
    ) {
      codes.push(...codesIn(node.right));
    }
    if (ts.isPropertyAssignment(node)) {
      const name = node.name.getText();
      if (
        ['reason', 'readiness', 'uncertainty'].includes(name) ||
        (file === 'rolling-schedule-signals.ts' && name === 'kind')
      ) {
        codes.push(...codesIn(node.initializer));
      }
    }
    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      node.expression.expression.getText() === 'reasons' &&
      node.expression.name.text === 'add'
    ) {
      codes.push(...node.arguments.flatMap(codesIn));
    }
    // The existing early-exit implementation emits event decisions, not a
    // separate reason union. Keep its end/shorten receipts in the same catalog.
    if (
      file === 'workout-actions.ts' &&
      ts.isCaseClause(node) &&
      ts.isStringLiteral(node.expression) &&
      ['end', 'shorten'].includes(node.expression.text)
    ) {
      const events = (child: ts.Node) => {
        if (ts.isPropertyAssignment(child) && child.name.getText() === 'kind') {
          codes.push(...codesIn(child.initializer));
        }
        ts.forEachChild(child, events);
      };
      ts.forEachChild(node, events);
    }
    ts.forEachChild(node, visit);
  }
  visit(parsed(file));
  return [...new Set(codes)];
}

const modules = [
  'rolling-session.ts',
  'rolling-schedule.ts',
  'rolling-schedule-signals.ts',
  'workout-actions.ts',
  'session-duration.ts',
];
const sourceCodes = () => [...new Set(modules.flatMap(emittedCodes))].sort();

const now = new Date('2026-10-26T07:00:00Z');
const rotation: RollingProgram = {
  sessions: [
    { id: 'A', muscles: ['chest'] },
    { id: 'B', muscles: ['chest'] },
    { id: 'C', muscles: ['quads'] },
  ],
  requestedExposures: 3,
  minHoursBetweenSessions: 0,
  muscleRecoveryHours: 48,
};

function durationFixture(): SessionDurationInput {
  const startedAt = now.toISOString();
  const session = buildSession({
    setup: {
      id: 'setup',
      consentVersion: TRAINING_CONSENT_VERSION,
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'full_gym',
      startedAt,
    },
    block: createMesoBlock(startedAt, startedAt),
    sessionId: 'session',
    slot: 0,
    logs: [],
    feedback: [],
  });
  session.exercises = [{ ...session.exercises[0]!, sets: 2 }];
  const exercise = session.exercises[0]!;
  return {
    session,
    eligibility: nextEligibleSession(rotation, { entries: [] }, now),
    priorityMuscles: [exercise.primaryMuscle],
    timing: {
      warmUpSeconds: 300,
      equipmentTransitionSeconds: 60,
      exercises: { [exercise.id]: { setSeconds: 60, restSeconds: 120, stationId: exercise.id } },
    },
    setSignals: { [exercise.id]: [{ marginalValue: 2 }, { marginalValue: 1 }] },
  };
}

describe('scheduler claim coverage contract (LYB-292)', () => {
  test.each(modules)('%s emits only codes with exactly one catalog sentence', (file) => {
    const codes = emittedCodes(file);
    expect(codes.length).toBeGreaterThan(0);
    for (const code of codes) {
      const entries = Object.entries(SCHEDULER_CLAIMS).filter(([key]) => key === code);
      expect({ code, sentences: entries.map(([, sentence]) => sentence) }).toEqual({
        code,
        sentences: [schedulerClaim(code)],
      });
      expect(schedulerClaim(code)).toMatch(/^[^.!?]+[.!?]$/);
    }
  });

  test('has no duplicate definitions, orphan codes, or free-form catalog entries', () => {
    const declared: string[] = [];
    function visit(node: ts.Node) {
      if (ts.isObjectLiteralExpression(node)) {
        for (const property of node.properties) {
          if (!ts.isPropertyAssignment(property) || !ts.isStringLiteral(property.initializer)) {
            throw new Error('Catalog entries must map one code to one literal sentence');
          }
          declared.push(property.name.getText());
        }
      }
      ts.forEachChild(node, visit);
    }
    visit(parsed('scheduler-claims.ts'));
    expect(declared.sort()).toEqual(sourceCodes());
    expect(Object.keys(SCHEDULER_CLAIMS).sort()).toEqual(sourceCodes());
  });

  test('resolves every queue, distribution, early-exit and duration fixture code', async () => {
    const observed = new Set<string>();
    const resolve = (codes: string[]) => {
      for (const code of codes) {
        expect(schedulerClaim(code)).toMatch(/^[^.!?]+[.!?]$/);
        observed.add(code);
      }
    };
    resolve([nextEligibleSession(rotation, { entries: [] }, now).reason]);
    for (const at of ['2026-10-20T07:00:00Z', '2026-10-26T06:00:00Z']) {
      resolve([
        nextEligibleSession(
          rotation,
          { entries: [{ sessionId: 'A', at, outcome: 'completed' }] },
          now,
        ).reason,
      ]);
    }

    const collectSchedule = (result: RollingScheduleReview) =>
      resolve([
        result.readiness,
        ...result.tradeoffs.map((row) => row.reason),
        ...result.dropped.map((row) => row.reason),
        ...result.unallocated.map((row) => row.reason),
        ...result.allocations.flatMap((row) => row.uncertainty),
        ...(result.attendanceChoice ? [result.attendanceChoice.kind] : []),
      ]);
    const review = (input = source()) =>
      collectSchedule(
        reviewRollingSchedule({
          sessions: input.sessions,
          context: input.rollingSchedule!,
          logs: input.logs ?? [],
          targetRir: 2,
        }),
      );
    review();
    const limited = source();
    limited.rollingSchedule!.requestedVisitsPerWeek = 2;
    review(limited);
    const reduced = source();
    reduced.rollingSchedule!.trials = [reduction()];
    review(reduced);
    const blocked = source();
    blocked.rollingSchedule!.slots.forEach((slot) => {
      slot.availableEquipment = [];
    });
    review(blocked);
    const continuation = source();
    Object.assign(continuation.rollingSchedule!.slots[0]!, {
      kind: 'continuation',
      continueSessionId: 'missing',
    });
    review(continuation);
    const existingVisit = source();
    existingVisit.rollingSchedule!.slots[0]!.visitId = history(existingVisit).visitId;
    review(existingVisit);
    const uncertain = source();
    history(uncertain, 'A', 0).outcome = 'unknown';
    history(uncertain, 'B', 1);
    uncertain.rollingSchedule!.observations = [
      {
        id: 'stale',
        at: '2026-09-01T08:00:00Z',
        scope: 'muscle',
        muscle: 'shoulders',
        state: 'limited',
      },
      { id: 'ready', at: now.toISOString(), scope: 'muscle', muscle: 'shoulders', state: 'ready' },
      {
        id: 'limited',
        at: now.toISOString(),
        scope: 'muscle',
        muscle: 'shoulders',
        state: 'limited',
      },
    ];
    review(uncertain);
    for (const visits of [1, 4]) {
      const attendance = source();
      const context = attendance.rollingSchedule!;
      context.asOf = '2026-10-29T00:00:00Z';
      context.attendanceSince = '2026-10-15T00:00:00Z';
      context.slots = [];
      for (let week = 0; week < 2; week++) {
        for (let day = 0; day < visits; day++) {
          const at = new Date(
            Date.parse(context.attendanceSince) + (week * 7 + day) * 86400000,
          ).toISOString();
          history(attendance, 'A', 1, at).rotationId = 'old';
        }
      }
      review(attendance);
    }

    for (const scenario of [
      'retained',
      'marginal',
      'fatigue',
      'recovery',
      'cap',
      'infeasible',
      'stopped',
    ]) {
      const input = durationFixture();
      const exercise = input.session.exercises[0]!;
      if (scenario === 'marginal')
        input.setSignals[exercise.id] = [{ marginalValue: 0 }, { marginalValue: 1 }];
      if (scenario === 'fatigue')
        input.setSignals[exercise.id] = [
          { marginalValue: 1, fatigueLimited: true },
          { marginalValue: 1 },
        ];
      if (scenario === 'recovery')
        input.recoveryLimit = { [exercise.primaryMuscle]: { maxFractionalSets: 0 } };
      if (scenario === 'cap') input.timeCapMinutes = 8;
      if (scenario === 'infeasible') input.timeCapMinutes = 1;
      if (scenario === 'stopped') input.session.safetyStop = true;
      resolve(planSessionDuration(input).reasonCodes);
    }

    for (const action of [{ kind: 'end' }, { kind: 'shorten', minutes: 10 }] as const) {
      const records = new MemoryTrainingRecords();
      await storeProgramSetup({
        records,
        subject: 'owner',
        now,
        setup: {
          adultConfirmed: true,
          safetyConfirmed: true,
          sessionsPerWeek: 2,
          equipment: 'dumbbells',
        },
        createId: () => '11111111-1111-4111-8111-000000000001',
      });
      const workout = await getOrCreateNextWorkout({
        records,
        subject: 'owner',
        now,
        persist: true,
      });
      if (workout.kind !== 'workout') throw new Error(`Expected workout: ${workout.kind}`);
      const result = await applyWorkoutAction({
        records,
        subject: 'owner',
        now,
        sessionId: workout.session.id,
        eventId: '22222222-2222-4222-8222-000000000001',
        expectedRevision: 0,
        action,
      });
      if (result.kind !== 'updated') throw new Error(`Expected early-exit receipt: ${result.kind}`);
      resolve([result.decision]);
    }
    expect([...observed].sort()).toEqual(sourceCodes());
  });
});
