import { stableTrainingUuid } from './service';
import type { RollingHistory, RollingHistoryEntry } from './rolling-session';
import { WEEK } from './rolling-schedule-signals';

/** Evidence window from LYB-174. Five-of-four consolidation stays at three weeks (LYB-259). */
export const ADHERENCE_WINDOW = { minWeeks: 2, maxWeeks: 4, consolidateWeeks: 3 } as const;

export type AdherenceSessionOutcome = 'completed' | 'partial' | 'missed' | 'empty' | 'unknown';

/** One recorded exposure. A continuation reuses `occurrenceId` and counts once in that week. */
export type AdherenceSessionRecord = {
  occurrenceId: string;
  at: string;
  outcome: AdherenceSessionOutcome;
};

/** LYB-123 fact that the exposure has logged work. History alone is not attendance. */
export type AdherenceCompletion = {
  occurrenceId: string;
};

/** Dated-outcome travel, or any explicit calendar disruption. It is not attendance. */
export type AdherenceDisruption = {
  kind: 'travel';
  /** Inclusive. A `YYYY-MM-DD` value is that UTC calendar date. */
  start: string;
  /** Exclusive when an instant. A `YYYY-MM-DD` value includes that UTC calendar date. */
  end: string;
};

export type AdherencePrescribedSession = {
  id: string;
  sets: number;
};

/** Requested capacity from the LYB-107 / LYB-130 setup. Detection does not write it. */
export type AdherenceProgramSnapshot = {
  id: string;
  sessionsPerWeek: 2 | 3 | 4 | 5 | 6;
  sessions: readonly AdherencePrescribedSession[];
  weeklySets: number;
};

export type AdherenceProposal = {
  id: string;
  kind: 'consolidate' | 'capacity_review';
  reversible: true;
  applied: false;
  requestedSessions: number;
  observedSessionsPerWeek: readonly number[];
  /** Repeated achieved count. This is a report, not a new prescription. */
  sustainableSessions: number;
  /** Null when the pattern is not a supported visit count. One visit is never suggested. */
  suggestedSessions: number | null;
  requestedAboveSustainable: true;
  patternStartedAt: string;
};

export type AdherenceDetection = {
  proposals: readonly AdherenceProposal[];
  program: AdherenceProgramSnapshot;
};

export type AdherenceWindowInput = {
  asOf: string;
  /** Start of the current requested-capacity epoch. Earlier programs are not supplied. */
  attendanceSince: string;
  sessions: readonly AdherenceSessionRecord[];
  completions: readonly AdherenceCompletion[];
  disruptions: readonly AdherenceDisruption[];
  program: AdherenceProgramSnapshot;
};

const ACHIEVED: ReadonlySet<AdherenceSessionOutcome> = new Set(['completed', 'partial']);
const DAY_MS = 24 * 60 * 60 * 1000;

/** Stable identity for one rolling-queue entry. Index keeps repeated template ids distinct. */
export function rollingOccurrenceId(entry: RollingHistoryEntry, index: number): string {
  return `${index}\0${entry.sessionId}\0${entry.at}\0${entry.outcome}`;
}

/** Session history from the rolling queue. Missed and empty entries stay in the record. */
export function sessionsFromRollingHistory(history: RollingHistory): AdherenceSessionRecord[] {
  return history.entries.map((entry, index) => ({
    occurrenceId: rollingOccurrenceId(entry, index),
    at: entry.at,
    outcome: entry.outcome,
  }));
}

function instant(value: string): number | null {
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const parsed = Date.parse(`${value}T00:00:00.000Z`);
    return Number.isFinite(parsed) ? parsed : null;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function exclusiveEnd(value: string): number | null {
  const start = instant(value);
  if (start === null) return null;
  return /^\d{4}-\d{2}-\d{2}$/.test(value) ? start + DAY_MS : start;
}

function none(program: AdherenceProgramSnapshot): AdherenceDetection {
  return { proposals: [], program };
}

type WeekSlot = {
  start: number;
  achieved: number;
  disrupted: boolean;
  unreliable: boolean;
};

function disrupted(
  start: number,
  end: number,
  disruptions: readonly AdherenceDisruption[],
): boolean | null {
  for (const disruption of disruptions) {
    const disruptionStart = instant(disruption.start);
    const disruptionEnd = exclusiveEnd(disruption.end);
    if (disruptionStart === null || disruptionEnd === null || disruptionEnd <= disruptionStart) {
      return null;
    }
    if (disruptionStart < end && disruptionEnd > start) return true;
  }
  return false;
}

function weeksOf(input: AdherenceWindowInput, since: number, count: number): WeekSlot[] | null {
  const corroborated = new Set(
    input.completions.map((fact) => fact.occurrenceId).filter((id) => id.trim().length > 0),
  );
  const slots: WeekSlot[] = [];
  for (let index = 0; index < count; index += 1) {
    const start = since + index * WEEK;
    const end = start + WEEK;
    const travel = disrupted(start, end, input.disruptions);
    if (travel === null) return null;
    const seen = new Set<string>();
    let achieved = 0;
    let unreliable = false;
    for (const session of input.sessions) {
      const at = instant(session.at);
      if (at === null) return null;
      if (at < start || at >= end) continue;
      if (session.outcome === 'unknown') {
        unreliable = true;
        continue;
      }
      if (!ACHIEVED.has(session.outcome) || !corroborated.has(session.occurrenceId)) continue;
      if (seen.has(session.occurrenceId)) continue;
      seen.add(session.occurrenceId);
      achieved += 1;
    }
    slots.push({ start, achieved, disrupted: travel, unreliable });
  }
  return slots;
}

function trailingRun(slots: readonly WeekSlot[]): WeekSlot[] {
  const run: WeekSlot[] = [];
  let achieved: number | null = null;
  for (let index = slots.length - 1; index >= 0; index -= 1) {
    const week = slots[index];
    if (!week || week.disrupted || week.unreliable) break;
    if (achieved === null) achieved = week.achieved;
    else if (week.achieved !== achieved) break;
    run.unshift(week);
  }
  return run;
}

function classify(
  weeks: number,
  requested: number,
  achieved: number,
): Pick<AdherenceProposal, 'kind' | 'suggestedSessions'> | null {
  if (achieved <= 0 || achieved >= requested) return null;
  if (requested === 5 && achieved === 4 && weeks >= ADHERENCE_WINDOW.consolidateWeeks) {
    return { kind: 'consolidate', suggestedSessions: achieved };
  }
  if (requested === 6 && achieved === 1 && weeks >= ADHERENCE_WINDOW.minWeeks) {
    return { kind: 'capacity_review', suggestedSessions: null };
  }
  return null;
}

/**
 * Compare requested weekly capacity with corroborated completions.
 * Emits at most one reversible proposal. The program snapshot is not copied or changed.
 * No user-facing sentence is chosen here.
 */
export function detectAdherenceWindow(input: AdherenceWindowInput): AdherenceDetection {
  const program = input.program;
  const since = instant(input.attendanceSince);
  const asOf = instant(input.asOf);
  if (since === null || asOf === null || asOf <= since) return none(program);
  const complete = Math.floor((asOf - since) / WEEK);
  if (complete < ADHERENCE_WINDOW.minWeeks) return none(program);

  const slots = weeksOf(input, since, complete);
  if (!slots) return none(program);
  const run = trailingRun(slots);
  const windowStart = slots.length - Math.min(ADHERENCE_WINDOW.maxWeeks, slots.length);
  const firstInWindow = slots[windowStart];
  if (!firstInWindow) return none(program);
  const observedWeeks = run.filter((week) => week.start >= firstInWindow.start);
  const achieved = observedWeeks[observedWeeks.length - 1]?.achieved;
  const patternStart = run[0];
  if (achieved === undefined || !patternStart || observedWeeks.length < ADHERENCE_WINDOW.minWeeks) {
    return none(program);
  }
  const matched = classify(observedWeeks.length, program.sessionsPerWeek, achieved);
  if (!matched || program.sessionsPerWeek <= achieved) return none(program);

  const patternStartedAt = new Date(patternStart.start).toISOString();
  const proposal: AdherenceProposal = {
    id: stableTrainingUuid(
      'lyb-291-adherence-window',
      program.id,
      matched.kind,
      String(program.sessionsPerWeek),
      String(achieved),
      patternStartedAt,
    ),
    kind: matched.kind,
    reversible: true,
    applied: false,
    requestedSessions: program.sessionsPerWeek,
    observedSessionsPerWeek: observedWeeks.map((week) => week.achieved),
    sustainableSessions: achieved,
    suggestedSessions: matched.suggestedSessions,
    requestedAboveSustainable: true,
    patternStartedAt,
  };
  return { proposals: [proposal], program };
}
