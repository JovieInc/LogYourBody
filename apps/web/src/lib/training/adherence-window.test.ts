import {
  detectAdherenceWindow,
  rollingOccurrenceId,
  sessionsFromRollingHistory,
  type AdherenceDetection,
  type AdherenceProgramSnapshot,
  type AdherenceSessionRecord,
  type AdherenceWindowInput,
} from './adherence-window';
import type { RollingHistory, RollingHistoryEntry, RollingSessionId } from './rolling-session';
import { WEEK } from './rolling-schedule-signals';

const SINCE = '2026-10-01T00:00:00.000Z';
const TEMPLATES: readonly RollingSessionId[] = ['A', 'B', 'C', 'D', 'E'];

function snapshot(sessionsPerWeek: 5 | 6): AdherenceProgramSnapshot {
  const sets = sessionsPerWeek === 5 ? [3, 4, 5, 2, 6] : [3, 4, 5, 2, 6, 4];
  return {
    id: 'program-291',
    sessionsPerWeek,
    sessions: sets.map((count, index) => ({ id: `prescribed-${index + 1}`, sets: count })),
    weeklySets: sets.reduce((total, count) => total + count, 0),
  };
}

function inputFor(
  counts: readonly number[],
  sessionsPerWeek: 5 | 6,
  options?: {
    disruptions?: readonly number[];
    dateDisruption?: { start: string; end: string };
    outcomes?: RollingHistoryEntry['outcome'];
    completions?: boolean;
    continuation?: boolean;
    unknownWeek?: number;
    asOf?: string;
  },
): AdherenceWindowInput {
  const since = Date.parse(SINCE);
  const entries: RollingHistoryEntry[] = [];
  counts.forEach((count, week) => {
    for (let day = 0; day < count; day += 1) {
      entries.push({
        sessionId: TEMPLATES[day % TEMPLATES.length]!,
        at: new Date(since + week * WEEK + day * 86_400_000).toISOString(),
        outcome: options?.outcomes ?? 'completed',
      });
    }
  });
  const history: RollingHistory = { entries };
  const sessions: AdherenceSessionRecord[] = sessionsFromRollingHistory(history);
  if (options?.unknownWeek !== undefined) {
    sessions.push({
      occurrenceId: `unknown-${options.unknownWeek}`,
      at: new Date(since + options.unknownWeek * WEEK).toISOString(),
      outcome: 'unknown',
    });
  }
  if (options?.continuation && sessions[0]) {
    sessions.push({ ...sessions[0], outcome: 'partial' });
  }
  const completions =
    options?.completions === false
      ? []
      : history.entries.map((entry, index) => ({
          occurrenceId: rollingOccurrenceId(entry, index),
        }));
  const disruptions = [
    ...(options?.disruptions ?? []).map((week) => ({
      kind: 'travel' as const,
      start: new Date(since + week * WEEK).toISOString(),
      end: new Date(since + (week + 1) * WEEK).toISOString(),
    })),
    ...(options?.dateDisruption ? [{ kind: 'travel' as const, ...options.dateDisruption }] : []),
  ];
  return {
    asOf: options?.asOf ?? new Date(since + counts.length * WEEK).toISOString(),
    attendanceSince: SINCE,
    sessions,
    completions,
    disruptions,
    program: snapshot(sessionsPerWeek),
  };
}

function detection(input: AdherenceWindowInput): {
  before: AdherenceProgramSnapshot;
  result: AdherenceDetection;
} {
  const before = JSON.parse(JSON.stringify(input.program)) as AdherenceProgramSnapshot;
  return { before, result: detectAdherenceWindow(input) };
}

function expectSameProgram(
  before: AdherenceProgramSnapshot,
  input: AdherenceWindowInput,
  result: AdherenceDetection,
) {
  expect(input.program).toEqual(before);
  expect(result.program).toEqual(before);
  expect(result.program.sessions).toEqual(before.sessions);
  expect(result.program.weeklySets).toBe(before.weeklySets);
  expect(result.program.sessionsPerWeek).toBe(before.sessionsPerWeek);
}

describe('adherence window detector (LYB-291)', () => {
  it('emits one consolidate proposal after three weeks at 4 of 5 and keeps the program', () => {
    const input = inputFor([4, 4, 4], 5, { continuation: true });
    const { before, result } = detection(input);
    expect(result.proposals).toHaveLength(1);
    expect(result.proposals[0]).toMatchObject({
      kind: 'consolidate',
      reversible: true,
      applied: false,
      requestedSessions: 5,
      observedSessionsPerWeek: [4, 4, 4],
      sustainableSessions: 4,
      suggestedSessions: 4,
      requestedAboveSustainable: true,
      patternStartedAt: SINCE,
    });
    expect(result.proposals[0]?.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    expect(Object.keys(result.proposals[0] ?? {}).sort()).toEqual(
      [
        'applied',
        'id',
        'kind',
        'observedSessionsPerWeek',
        'patternStartedAt',
        'requestedAboveSustainable',
        'requestedSessions',
        'reversible',
        'suggestedSessions',
        'sustainableSessions',
      ].sort(),
    );
    expectSameProgram(before, input, result);
  });

  it('keeps a single proposal id when the same window is detected twice', () => {
    const input = inputFor([4, 4, 4], 5);
    const first = detectAdherenceWindow(input);
    const second = detectAdherenceWindow(input);
    const later = detectAdherenceWindow({
      ...input,
      asOf: new Date(Date.parse(SINCE) + 3 * WEEK + 2 * 86_400_000).toISOString(),
      sessions: [
        ...input.sessions,
        {
          occurrenceId: 'incomplete-week',
          at: new Date(Date.parse(SINCE) + 3 * WEEK + 86_400_000).toISOString(),
          outcome: 'completed',
        },
      ],
    });
    expect(first.proposals).toHaveLength(1);
    expect(second.proposals).toHaveLength(1);
    expect(later.proposals).toHaveLength(1);
    expect(
      new Set([first.proposals[0]?.id, second.proposals[0]?.id, later.proposals[0]?.id]).size,
    ).toBe(1);
  });

  it('keeps that id when the same pattern runs past the four-week window', () => {
    const first = detectAdherenceWindow(inputFor([4, 4, 4, 4], 5));
    const extended = detectAdherenceWindow(inputFor([4, 4, 4, 4, 4], 5));
    expect(first.proposals).toHaveLength(1);
    expect(extended.proposals).toHaveLength(1);
    expect(extended.proposals[0]?.observedSessionsPerWeek).toEqual([4, 4, 4, 4]);
    expect(extended.proposals[0]?.id).toBe(first.proposals[0]?.id);
    expect(extended.proposals[0]?.patternStartedAt).toBe(SINCE);
  });

  it('emits one capacity-review proposal for 6 requested and 1 achieved without changing volume', () => {
    const input = inputFor([1, 1, 1], 6);
    const { before, result } = detection(input);
    expect(result.proposals).toHaveLength(1);
    expect(result.proposals[0]).toMatchObject({
      kind: 'capacity_review',
      reversible: true,
      applied: false,
      requestedSessions: 6,
      observedSessionsPerWeek: [1, 1, 1],
      sustainableSessions: 1,
      suggestedSessions: null,
      requestedAboveSustainable: true,
    });
    expect(before.weeklySets).toBe(24);
    expect(before.sessions).toHaveLength(6);
    expectSameProgram(before, input, result);
  });

  it('emits nothing for one missed week', () => {
    const input = inputFor([5, 5, 4], 5);
    const { before, result } = detection(input);
    expect(result.proposals).toEqual([]);
    expectSameProgram(before, input, result);
  });

  it('does not treat two weeks at 4 of 5 as a consolidate pattern', () => {
    const { result } = detection(inputFor([4, 4], 5));
    expect(result.proposals).toEqual([]);
  });

  it('emits no consolidate proposal when a travel week interrupts the run', () => {
    const input = inputFor([4, 4, 4], 5, {
      dateDisruption: { start: '2026-10-08', end: '2026-10-14' },
    });
    const { before, result } = detection(input);
    expect(result.proposals.filter((proposal) => proposal.kind === 'consolidate')).toEqual([]);
    expect(result.proposals).toEqual([]);
    expectSameProgram(before, input, result);
  });

  it('does not let an earlier travel week become the attendance pattern', () => {
    const input = inputFor([1, 4, 4, 4], 5, { disruptions: [0] });
    const { result } = detection(input);
    expect(result.proposals).toHaveLength(1);
    expect(result.proposals[0]).toMatchObject({
      kind: 'consolidate',
      observedSessionsPerWeek: [4, 4, 4],
    });
    expect(result.proposals[0]?.patternStartedAt).toBe(
      new Date(Date.parse(SINCE) + WEEK).toISOString(),
    );
  });

  it('emits nothing for full attendance', () => {
    const input = inputFor([5, 5, 5], 5);
    const { before, result } = detection(input);
    expect(result.proposals).toEqual([]);
    expectSameProgram(before, input, result);
  });

  it('ignores completed queue rows that have no completion fact', () => {
    const { result } = detection(inputFor([4, 4, 4], 5, { completions: false }));
    expect(result.proposals).toEqual([]);
  });

  it.each(['missed', 'empty'] as const)(
    'does not count %s sessions as achieved attendance',
    (outcome) => {
      const { result } = detection(inputFor([4, 4, 4], 5, { outcomes: outcome }));
      expect(result.proposals).toEqual([]);
    },
  );

  it('withholds the pattern when the newest week has unknown attendance', () => {
    const { result } = detection(inputFor([4, 4, 4], 5, { unknownWeek: 2 }));
    expect(result.proposals).toEqual([]);
  });

  it('counts a partial exposure once when a completion fact corroborates it', () => {
    const input = inputFor([4, 4, 4], 5, { outcomes: 'completed' });
    input.sessions.forEach((session) => {
      session.outcome = 'partial';
    });
    const { result } = detection(input);
    expect(result.proposals).toHaveLength(1);
    expect(result.proposals[0]?.kind).toBe('consolidate');
    expect(result.proposals[0]?.observedSessionsPerWeek).toEqual([4, 4, 4]);
  });

  it('fails closed when a session instant cannot be placed', () => {
    const input = inputFor([4, 4, 4], 5);
    input.sessions[0]!.at = 'not-a-time';
    expect(detectAdherenceWindow(input).proposals).toEqual([]);
  });
});
