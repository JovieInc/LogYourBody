import {
  nextEligibleSession,
  type NextEligibleSession,
  type RollingHistory,
  type RollingHistoryEntry,
  type RollingProgram,
  type RollingSessionId,
} from './rolling-session';

const DAY_MS = 24 * 60 * 60 * 1000;

/** Disjoint muscles so a daily rotation is not rewritten by the recovery window. */
function rotation(requestedExposures: RollingProgram['requestedExposures']): RollingProgram {
  return {
    sessions: [
      { id: 'A', muscles: ['chest'] },
      { id: 'B', muscles: ['back'] },
      { id: 'C', muscles: ['quads'] },
      { id: 'D', muscles: ['hamstrings'] },
      { id: 'E', muscles: ['glutes'] },
    ],
    requestedExposures,
    minHoursBetweenSessions: 12,
    muscleRecoveryHours: 48,
  };
}

function at(iso: string, days: number): string {
  return new Date(Date.parse(iso) + days * DAY_MS).toISOString();
}

function done(sessionId: RollingSessionId, iso: string): RollingHistoryEntry {
  return { sessionId, at: iso, outcome: 'completed' };
}

function select(
  program: RollingProgram,
  history: RollingHistory,
  iso: string,
): NextEligibleSession {
  return nextEligibleSession(program, history, new Date(iso));
}

function expectSession(program: RollingProgram, result: NextEligibleSession, id: RollingSessionId) {
  expect(program.sessions.map((session) => session.id)).toContain(result.sessionId);
  expect(result.sessionId).toBe(id);
  expect(result.index).toBe(program.sessions.findIndex((session) => session.id === id));
}

describe('rolling session selector', () => {
  test('an 8-day rotation crossing a weekend is the same from Friday and from Monday', () => {
    const program = rotation(5);
    const starts = ['2026-10-23T15:00:00.000Z', '2026-10-26T15:00:00.000Z'];
    const sequences = starts.map((start) => {
      const history: RollingHistoryEntry[] = [];
      const chosen: RollingSessionId[] = [];
      for (let day = 0; day < 8; day += 1) {
        const now = at(start, day);
        const next = select(program, { entries: history }, now);
        expectSession(program, next, (['A', 'B', 'C', 'D', 'E', 'A', 'B', 'C'] as const)[day]!);
        expect(next.eligibleNow).toBe(true);
        chosen.push(next.sessionId);
        history.push(done(next.sessionId, now));
      }
      const weekdays = Array.from({ length: 8 }, (_, day) => new Date(at(start, day)).getUTCDay());
      expect(weekdays).toEqual(expect.arrayContaining([6, 0]));
      return chosen;
    });
    expect(sequences[0]).toEqual(['A', 'B', 'C', 'D', 'E', 'A', 'B', 'C']);
    expect(sequences[1]).toEqual(sequences[0]);
  });

  test('two missed workouts stay on the session after the last completion', () => {
    const program = rotation(5);
    const history: RollingHistory = {
      entries: [
        done('C', '2026-10-23T15:00:00.000Z'),
        { sessionId: 'D', at: '2026-10-24T15:00:00.000Z', outcome: 'missed' },
        { sessionId: 'E', at: '2026-10-25T15:00:00.000Z', outcome: 'missed' },
      ],
    };
    const monday = select(program, history, '2026-10-26T15:00:00.000Z');
    const saturday = select(
      program,
      {
        entries: history.entries.map((entry) => ({ ...entry, at: at(entry.at, 5) })),
      },
      '2026-10-31T15:00:00.000Z',
    );
    expectSession(program, monday, 'D');
    expect(monday.reason).toBe('next_after_last_completion');
    expect(saturday.sessionId).toBe(monday.sessionId);
    expect(saturday.reason).toBe(monday.reason);
    expect(Date.parse(saturday.eligibleAt) - Date.parse('2026-10-31T15:00:00.000Z')).toBe(
      Date.parse(monday.eligibleAt) - Date.parse('2026-10-26T15:00:00.000Z'),
    );
  });

  test.each([
    { requested: 5 as const, achieved: 0, expected: 'A' as const },
    { requested: 5 as const, achieved: 1, expected: 'B' as const },
    { requested: 5 as const, achieved: 2, expected: 'C' as const },
    { requested: 5 as const, achieved: 3, expected: 'D' as const },
    { requested: 5 as const, achieved: 4, expected: 'E' as const },
    { requested: 6 as const, achieved: 0, expected: 'A' as const },
    { requested: 6 as const, achieved: 1, expected: 'B' as const },
    { requested: 6 as const, achieved: 5, expected: 'A' as const },
  ])(
    '$requested requested / $achieved achieved selects $expected',
    ({ requested, achieved, expected }) => {
      const program = rotation(requested);
      const ids: RollingSessionId[] = ['A', 'B', 'C', 'D', 'E'];
      const history: RollingHistory = {
        entries: ids
          .slice(0, achieved)
          .map((sessionId, index) => done(sessionId, at('2026-10-23T15:00:00.000Z', index))),
      };
      const now = at('2026-10-23T15:00:00.000Z', achieved);
      const next = select(program, history, now);
      expectSession(program, next, expected);
      expect(next.eligibleNow).toBe(true);
    },
  );

  test('the same inputs return the same session', () => {
    const program = rotation(6);
    const history: RollingHistory = {
      entries: [
        done('A', '2026-10-23T15:00:00.000Z'),
        { sessionId: 'B', at: '2026-10-24T15:00:00.000Z', outcome: 'empty' },
        done('A', '2026-10-20T15:00:00.000Z'),
      ],
    };
    const now = new Date('2026-10-26T18:00:00.000Z');
    const first = nextEligibleSession(program, history, now);
    const second = nextEligibleSession(program, history, now);
    const reversed = nextEligibleSession(program, { entries: [...history.entries].reverse() }, now);
    expect(second).toEqual(first);
    expect(reversed).toEqual(first);
    expect(first.sessionId).toBe('B');
  });

  test('recent stimulus yields to the next clear session until the window elapses', () => {
    const program: RollingProgram = {
      ...rotation(5),
      sessions: [
        { id: 'A', muscles: ['chest', 'shoulders'] },
        { id: 'B', muscles: ['shoulders', 'triceps'] },
        { id: 'C', muscles: ['quads'] },
        { id: 'D', muscles: ['back'] },
        { id: 'E', muscles: ['biceps'] },
      ],
    };
    const completedAt = '2026-10-23T15:00:00.000Z';
    const history: RollingHistory = { entries: [done('A', completedAt)] };
    // Six hours later the gap has not elapsed, and B still shares shoulders with A.
    const inside = select(program, history, '2026-10-23T21:00:00.000Z');
    const recent = select(program, history, '2026-10-24T11:00:00.000Z');
    const cleared = select(program, history, '2026-10-25T15:00:00.000Z');
    expectSession(program, inside, 'C');
    expect(inside.reason).toBe('skipped_recent_stimulus');
    expect(inside.eligibleNow).toBe(false);
    expect(inside.eligibleAt).toBe('2026-10-24T03:00:00.000Z');
    expectSession(program, recent, 'C');
    expect(recent.reason).toBe('skipped_recent_stimulus');
    expect(recent.eligibleNow).toBe(true);
    expectSession(program, cleared, 'B');
    expect(cleared.reason).toBe('next_after_last_completion');
    expect(cleared.eligibleNow).toBe(true);
  });

  test('a full stimulus overlap keeps the successor instead of restarting', () => {
    const program: RollingProgram = {
      ...rotation(5),
      sessions: [
        { id: 'A', muscles: ['shoulders'] },
        { id: 'B', muscles: ['shoulders'] },
        { id: 'C', muscles: ['shoulders'] },
        { id: 'D', muscles: ['shoulders'] },
        { id: 'E', muscles: ['shoulders'] },
      ],
    };
    const next = select(
      program,
      { entries: [done('A', '2026-10-23T15:00:00.000Z')] },
      '2026-10-23T16:00:00.000Z',
    );
    expectSession(program, next, 'B');
    expect(next.reason).toBe('next_after_last_completion');
    expect(next.eligibleNow).toBe(false);
    expect(next.eligibleAt).toBe('2026-10-25T15:00:00.000Z');
  });

  test('an empty-ended session does not advance and does not restart', () => {
    const program = rotation(5);
    const next = select(
      program,
      {
        entries: [
          done('A', '2026-10-23T15:00:00.000Z'),
          { sessionId: 'B', at: '2026-10-24T15:00:00.000Z', outcome: 'empty' },
        ],
      },
      '2026-10-25T15:00:00.000Z',
    );
    expectSession(program, next, 'B');
    expect(next.reason).toBe('next_after_last_completion');
  });

  test('a short gap keeps the successor and reports when it is due', () => {
    const program = rotation(5);
    const completedAt = '2026-10-24T08:00:00.000Z';
    const tooSoon = select(
      program,
      { entries: [done('A', completedAt)] },
      '2026-10-24T14:00:00.000Z',
    );
    const due = select(program, { entries: [done('A', completedAt)] }, '2026-10-24T20:00:00.000Z');
    expectSession(program, tooSoon, 'B');
    expect(tooSoon.eligibleNow).toBe(false);
    expect(tooSoon.eligibleAt).toBe('2026-10-24T20:00:00.000Z');
    expectSession(program, due, 'B');
    expect(due.eligibleNow).toBe(true);
  });
});
