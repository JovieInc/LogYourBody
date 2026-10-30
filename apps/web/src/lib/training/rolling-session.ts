import { MUSCLE_GROUPS, type MuscleGroup } from './types';

/**
 * Next exposure in an ordered A..E rotation (LYB-258).
 *
 * LYB-130 does not count missed or empty-ended workouts as training, and a
 * delegated block does not complete from calendar time alone. LYB-115 advances
 * a configured cycle from completed sessions rather than elapsed weeks. This
 * selector uses that same cursor for the next exposure: the latest completion
 * in an ordered A..E rotation. It does not write program state and it does
 * not read a weekday. Callers pass the rotation already ordered.
 *
 * `muscleRecoveryHours` and `minHoursBetweenSessions` are caller-supplied
 * bounds. They are not an inferred personal recovery time. Overlap with a
 * recent stimulus moves forward to the next ordered session whose muscles
 * are outside that window. When every session still overlaps, the sequential
 * successor stays the result so a miss cannot restart the cycle.
 */

export const ROLLING_SESSION_IDS = ['A', 'B', 'C', 'D', 'E'] as const;
export type RollingSessionId = (typeof ROLLING_SESSION_IDS)[number];

const HOUR_MS = 60 * 60 * 1000;
const REQUESTED_EXPOSURES = [2, 3, 4, 5, 6] as const;

/** A deferred template stays pending even when another eligible template goes
 * first. Both the selector and optimizer use the same completion cursor. */
export function rollingSessionOrder<T extends string>(ids: readonly T[], last?: string): T[] {
  const index = last === undefined ? -1 : ids.indexOf(last as T);
  const start = (index + 1) % ids.length;
  return [...ids.slice(start), ...ids.slice(0, start)];
}

export type RollingSessionTemplate = {
  id: RollingSessionId;
  muscles: readonly MuscleGroup[];
};

export type RollingProgram = {
  /** Unique A..E ids in that order. Length may be shorter than `requestedExposures`. */
  sessions: readonly RollingSessionTemplate[];
  /** User-requested exposures per cycle (delegated planning allows 2..6). */
  requestedExposures: (typeof REQUESTED_EXPOSURES)[number];
  /** Hours after the last completion before the next exposure is due. Zero allows a later same-day session. */
  minHoursBetweenSessions: number;
  /** Hours after a muscle is stimulated before another session training it is preferred. */
  muscleRecoveryHours: number;
};

export type RollingHistoryEntry = {
  sessionId: string;
  at: string;
  /** Only `completed` moves the cursor. `missed` and `empty` do not. */
  outcome: 'completed' | 'missed' | 'empty';
  /** Logged muscles. Omitted uses the template. An unknown muscle drops the entry. */
  muscles?: readonly string[];
};

export type RollingHistory = {
  entries: readonly RollingHistoryEntry[];
};

export type RollingSelectionReason =
  'first_exposure' | 'next_after_last_completion' | 'skipped_recent_stimulus';

export type NextEligibleSession = {
  sessionId: RollingSessionId;
  index: number;
  reason: RollingSelectionReason;
  /** Instant the gap and this session's muscle window are both clear. */
  eligibleAt: string;
  eligibleNow: boolean;
};

function isMuscleGroup(value: string): value is MuscleGroup {
  return (MUSCLE_GROUPS as readonly string[]).includes(value);
}

function isSessionId(value: string): value is RollingSessionId {
  return (ROLLING_SESSION_IDS as readonly string[]).includes(value);
}

function assertProgram(program: RollingProgram): void {
  const ids = program.sessions.map((session) => session.id);
  const positions = ids.map((id) => ROLLING_SESSION_IDS.indexOf(id));
  const requestedOk = (REQUESTED_EXPOSURES as readonly number[]).includes(
    program.requestedExposures,
  );
  const hoursOk =
    Number.isFinite(program.minHoursBetweenSessions) &&
    program.minHoursBetweenSessions >= 0 &&
    Number.isFinite(program.muscleRecoveryHours) &&
    program.muscleRecoveryHours >= 0;
  const ordered =
    ids.length > 0 &&
    ids.length <= ROLLING_SESSION_IDS.length &&
    new Set(ids).size === ids.length &&
    positions.every(
      (position, index) => position >= 0 && (index === 0 || position > positions[index - 1]!),
    );
  const musclesOk = program.sessions.every((session) =>
    session.muscles.every((muscle) => isMuscleGroup(muscle)),
  );
  if (!requestedOk || !hoursOk || !ordered || !musclesOk) {
    throw new Error('rolling_session_program_invalid');
  }
}

type CountedCompletion = {
  sessionId: RollingSessionId;
  at: number;
  muscles: readonly MuscleGroup[];
  order: number;
};

function completions(
  program: RollingProgram,
  history: RollingHistory,
  nowMs: number,
): CountedCompletion[] {
  const byId = new Map(program.sessions.map((session) => [session.id, session]));
  const counted: CountedCompletion[] = [];
  history.entries.forEach((entry, order) => {
    if (entry.outcome !== 'completed' || !isSessionId(entry.sessionId)) return;
    const template = byId.get(entry.sessionId);
    if (!template) return;
    const at = Date.parse(entry.at);
    if (!Number.isFinite(at) || at > nowMs) return;
    if (entry.muscles?.some((muscle) => !isMuscleGroup(muscle))) return;
    counted.push({
      sessionId: entry.sessionId,
      at,
      muscles: entry.muscles ? entry.muscles.filter(isMuscleGroup) : template.muscles,
      order,
    });
  });
  counted.sort((a, b) => a.at - b.at || a.order - b.order);
  return counted;
}

function lastStimulus(muscle: MuscleGroup, rows: readonly CountedCompletion[]): number | null {
  let latest: number | null = null;
  for (const row of rows) {
    if (!row.muscles.includes(muscle)) continue;
    if (latest === null || row.at > latest) latest = row.at;
  }
  return latest;
}

function stimulusBlocks(
  session: RollingSessionTemplate,
  rows: readonly CountedCompletion[],
  nowMs: number,
  recoveryMs: number,
): boolean {
  if (recoveryMs <= 0) return false;
  return session.muscles.some((muscle) => {
    const latest = lastStimulus(muscle, rows);
    return latest !== null && nowMs - latest < recoveryMs;
  });
}

function readyAt(
  session: RollingSessionTemplate,
  rows: readonly CountedCompletion[],
  gapReady: number,
  recoveryMs: number,
): number {
  let ready = gapReady;
  if (recoveryMs <= 0) return ready;
  for (const muscle of session.muscles) {
    const latest = lastStimulus(muscle, rows);
    if (latest !== null) ready = Math.max(ready, latest + recoveryMs);
  }
  return ready;
}

export function nextEligibleSession(
  program: RollingProgram,
  history: RollingHistory,
  now: Date,
): NextEligibleSession {
  assertProgram(program);
  const nowMs = now.getTime();
  if (!Number.isFinite(nowMs)) throw new Error('rolling_session_now_invalid');

  const rows = completions(program, history, nowMs);
  const last = rows[rows.length - 1];
  const sessions = program.sessions;
  const nextId = rollingSessionOrder(
    sessions.map((session) => session.id),
    last?.sessionId,
  )[0];
  const start = sessions.findIndex((session) => session.id === nextId);
  let index = start;
  let reason: RollingSelectionReason = last ? 'next_after_last_completion' : 'first_exposure';
  const recoveryMs = program.muscleRecoveryHours * HOUR_MS;
  if (last) {
    for (let step = 0; step < sessions.length; step += 1) {
      const candidate = (start + step) % sessions.length;
      if (!stimulusBlocks(sessions[candidate]!, rows, nowMs, recoveryMs)) {
        index = candidate;
        if (step > 0) reason = 'skipped_recent_stimulus';
        break;
      }
    }
  }

  const chosen = sessions[index]!;
  const gapReady = last ? last.at + program.minHoursBetweenSessions * HOUR_MS : nowMs;
  const eligibleMs = last ? readyAt(chosen, rows, gapReady, recoveryMs) : nowMs;
  return {
    sessionId: chosen.id,
    index,
    reason,
    eligibleAt: new Date(eligibleMs).toISOString(),
    eligibleNow: eligibleMs <= nowMs,
  };
}
