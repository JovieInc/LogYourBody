import {
  evaluateDeload,
  hasConflictingFeedbackAtSameTime,
  latestFeedbackPerSession,
} from './engine';
import type { MesoBlock, TrainingFeedback, TrainingProgramSetup } from './types';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Reviewed deterministic policy bounds. The controller interprets evidence and
 * chooses the minimum effective intervention inside these bounds; it never
 * invents physiological limits, diagnoses, or numeric prescriptions.
 */
export const CONTROLLER_POLICY = {
  /** Recovery/performance evidence older than this is stale, not non-adherence. */
  staleSignalDays: 14,
  /** Weeks at the start of a block where decline triggers investigation, never auto-deload. */
  earlyBlockWeeks: 2,
  /** Consecutive declining sessions that make recovery an investigation candidate. */
  declineInvestigationCount: 2,
  /** Corroborating soreness (0-10) required before a late-block deload proposal. */
  deloadSorenessThreshold: 7,
  /** Weight-trend decisions need at least this many points spanning this many days. */
  minTrendPoints: 3,
  minTrendSpanDays: 14,
} as const;

const TRAJECTORY_EVIDENCE = ['k:76bf778c', 'k:b1e1dc5b', 'k:e95f2199'];
const ADHERENCE_EVIDENCE = ['k:81c218db', 'k:45b5a80f'];
const LOAD_CORRECTION_EVIDENCE = ['k:88ea9e15', 'k:a6ae7fd4'];
const HOLD_EVIDENCE = ['k:81c218db', 'k:ed46b889'];

export type SignalFreshness = 'fresh' | 'stale' | 'missing';

export type WeightPoint = { date: string; weightKg: number };

export type GoalTrajectory = {
  /** User-selected target rate band in kg/week, e.g. { min: -0.75, max: -0.25 }. */
  targetRateKgPerWeek: { min: number; max: number };
  points: WeightPoint[];
};

/** Situational constraints expire and are never promoted to durable preferences. */
export type SituationalConstraint = {
  id: string;
  kind: 'time_cap' | 'equipment_unavailable' | 'travel' | 'readiness_low' | 'readiness_high';
  detail: string;
  expiresAt: string;
};

export type ControllerDecision =
  | { kind: 'hold'; optionalBurdenReduction: boolean }
  | { kind: 'adjust_training'; adjustment: 'pause_session' | 'shorten_session' | 'load_correction' }
  | { kind: 'adjust_activity' }
  | { kind: 'recovery_proposal'; proposal: 'deload_microcycle'; requiresConfirmation: true }
  | { kind: 'reschedule'; missedSessions: number }
  | { kind: 'ask_question'; question: string };

/** Evidence → decision → state change → next-action receipt, recorded for every decision including hold. */
export type ControllerReceipt = {
  decision: ControllerDecision;
  actor: 'controller';
  rationale: string;
  signalFreshness: {
    training: SignalFreshness;
    recovery: SignalFreshness;
    trajectory: SignalFreshness;
  };
  evidenceIds: string[];
  /** Human-readable plan state before and after the decision. */
  before: string;
  after: string;
  reviewPoint: string;
  nextAction: string;
};

export type ControllerInput = {
  setup: TrainingProgramSetup;
  block: MesoBlock;
  sessions: Array<{ status?: string; startedAt?: string; server_updated_at: string }>;
  feedback: TrainingFeedback[];
  completedThisWeek: number;
  /** Sessions the plan expected to be done by now this week. */
  plannedSessionsByNow: number;
  trajectory?: GoalTrajectory | null;
  constraints?: SituationalConstraint[];
  now: Date;
};

const time = (value: string) => Date.parse(value);

function freshness(latestAt: string | null, now: Date): SignalFreshness {
  if (!latestAt || !Number.isFinite(time(latestAt))) return 'missing';
  return now.getTime() - time(latestAt) <= CONTROLLER_POLICY.staleSignalDays * DAY_MS
    ? 'fresh'
    : 'stale';
}

/** Returns only unexpired situational constraints. Nothing here mutates durable setup. */
export function activeConstraints(
  constraints: SituationalConstraint[] | undefined,
  now: Date,
): SituationalConstraint[] {
  return (constraints ?? []).filter(
    (constraint) =>
      Number.isFinite(time(constraint.expiresAt)) && time(constraint.expiresAt) > now.getTime(),
  );
}

function weeklyRateKg(points: WeightPoint[]): number | null {
  const ordered = [...points]
    .filter(
      (point) =>
        Number.isFinite(time(point.date)) && Number.isFinite(point.weightKg) && point.weightKg > 0,
    )
    .sort((a, b) => time(a.date) - time(b.date));
  if (ordered.length < CONTROLLER_POLICY.minTrendPoints) return null;
  const first = ordered[0]!;
  const last = ordered[ordered.length - 1]!;
  const spanDays = (time(last.date) - time(first.date)) / DAY_MS;
  if (spanDays < CONTROLLER_POLICY.minTrendSpanDays) return null;
  return ((last.weightKg - first.weightKg) / spanDays) * 7;
}

function consecutiveDeclines(feedback: TrainingFeedback[]): number {
  const ordered = latestFeedbackPerSession(feedback);
  let count = 0;
  for (const item of ordered) {
    if (item.performance !== 'down') break;
    count += 1;
  }
  return count;
}

function receipt(partial: Omit<ControllerReceipt, 'actor'>): ControllerReceipt {
  return { actor: 'controller', ...partial };
}

const ON_TRACK = "You're on track. Nothing needs changing today.";

/**
 * Deterministic trajectory → bounded adaptation/hold → one next action.
 * Pure: it reads canonical signals and durable setup but never mutates them.
 */
export function evaluateTrajectory(input: ControllerInput): ControllerReceipt {
  const now = input.now;
  const latestSessionAt =
    input.sessions
      .map((session) => session.startedAt ?? session.server_updated_at)
      .filter((value): value is string => typeof value === 'string')
      .sort((a, b) => time(b) - time(a))[0] ?? null;
  const orderedFeedback = latestFeedbackPerSession(input.feedback);
  const trainingFresh = freshness(latestSessionAt, now);
  const recoveryFresh = freshness(orderedFeedback[0]?.createdAt ?? null, now);
  const trajectoryRate = input.trajectory ? weeklyRateKg(input.trajectory.points) : null;
  const trajectoryFresh: SignalFreshness = !input.trajectory
    ? 'missing'
    : trajectoryRate === null
      ? 'missing'
      : freshness(input.trajectory.points[input.trajectory.points.length - 1]?.date ?? null, now);
  const signalFreshness = {
    training: trainingFresh,
    recovery: recoveryFresh,
    trajectory: trajectoryFresh,
  };
  const plan = `${input.setup.sessionsPerWeek} sessions/week, week ${input.block.currentWeek} of ${input.block.weekCount}`;

  const deload = evaluateDeload(input.feedback);
  if (deload.action === 'pause_session') {
    return receipt({
      decision: { kind: 'adjust_training', adjustment: 'pause_session' },
      rationale: deload.explanation,
      signalFreshness,
      evidenceIds: deload.evidenceIds,
      before: plan,
      after: 'Current session paused pending review of the reported pain.',
      reviewPoint: 'Before the next training session',
      nextAction:
        'Pause the affected exercise today. If the pain persists or worsens, seek qualified clinical guidance.',
    });
  }

  // Recovery-decline investigation: repeated decline is a candidate for context
  // review, not an automatic deload. Stale or contradictory check-ins force no change.
  const declines =
    recoveryFresh === 'fresh' && input.feedback.length > 0
      ? consecutiveDeclines(input.feedback)
      : 0;
  const recentContradiction = orderedFeedback
    .slice(0, 2)
    .some((item) => hasConflictingFeedbackAtSameTime(item, input.feedback));
  const corroborated =
    declines >= CONTROLLER_POLICY.declineInvestigationCount &&
    (orderedFeedback[0]?.soreness ?? 0) >= CONTROLLER_POLICY.deloadSorenessThreshold;
  if (declines >= CONTROLLER_POLICY.declineInvestigationCount && !recentContradiction) {
    if (input.block.currentWeek <= CONTROLLER_POLICY.earlyBlockWeeks) {
      if (corroborated) {
        return receipt({
          decision: { kind: 'adjust_training', adjustment: 'load_correction' },
          rationale:
            'Performance has declined repeatedly early in the block with high soreness. Early-block decline points at setup (starting loads, fueling, sleep) rather than accumulated fatigue, so the bounded correction is one load step down — not a new block or deload.',
          signalFreshness,
          evidenceIds: LOAD_CORRECTION_EVIDENCE,
          before: plan,
          after: 'Next session uses one available load increment lower on the declining lifts.',
          reviewPoint: 'After the next session check-in',
          nextAction:
            'Run your next session one load increment lighter on the lifts that have been declining.',
        });
      }
      return receipt({
        decision: {
          kind: 'ask_question',
          question:
            'Performance has dipped early in this block. Has anything changed — sleep, food, stress, or were the starting loads too heavy?',
        },
        rationale:
          'Repeated early-block decline is an investigation candidate. With no corroborating recovery signal, one clarifying question beats a reflexive plan change.',
        signalFreshness,
        evidenceIds: TRAJECTORY_EVIDENCE,
        before: plan,
        after: 'Plan unchanged pending your answer.',
        reviewPoint: 'At your reply or the next session',
        nextAction: 'Answer the one question above, then train as planned.',
      });
    }
    if (corroborated) {
      return receipt({
        decision: {
          kind: 'recovery_proposal',
          proposal: 'deload_microcycle',
          requiresConfirmation: true,
        },
        rationale:
          'Performance has declined repeatedly late in the block with high soreness — multiple trustworthy signals agree. A bounded one-microcycle deload is proposed for confirmation.',
        signalFreshness,
        evidenceIds: ['k:0b3ea5bb', ...TRAJECTORY_EVIDENCE],
        before: plan,
        after: 'Proposed: one microcycle at one set per movement, then resume the block.',
        reviewPoint: 'End of the deload microcycle',
        nextAction: 'Confirm the one-week deload (one set per movement), or keep the current plan.',
      });
    }
    return receipt({
      decision: { kind: 'hold', optionalBurdenReduction: false },
      rationale:
        'Performance declined but recovery check-ins do not corroborate accumulated fatigue. No change is warranted yet; decline alone is not a deload trigger.',
      signalFreshness,
      evidenceIds: TRAJECTORY_EVIDENCE,
      before: plan,
      after: 'Plan unchanged.',
      reviewPoint: 'Next session check-in',
      nextAction: ON_TRACK,
    });
  }

  // Temporary life disruption: situational, expiring constraints bound today's dose
  // without touching durable preferences. High readiness never escalates the plan.
  const constraints = activeConstraints(input.constraints, now);
  const limited = constraints.find(
    (constraint) => constraint.kind === 'time_cap' || constraint.kind === 'readiness_low',
  );
  if (limited) {
    return receipt({
      decision: { kind: 'adjust_training', adjustment: 'shorten_session' },
      rationale: `A temporary constraint applies (${limited.detail}). Shortening today's session preserves continuity; durable preferences are unchanged.`,
      signalFreshness,
      evidenceIds: HOLD_EVIDENCE,
      before: plan,
      after: "Today's session is shortened to one set per movement.",
      reviewPoint: 'Next scheduled session',
      nextAction:
        'Do a shortened session today — one hard set per movement beats skipping the day.',
    });
  }

  // Missed sessions are replanned forward, never punished with catch-up volume.
  // Missing or stale training evidence is an evidence gap, not non-adherence.
  const missed =
    trainingFresh === 'fresh'
      ? Math.max(0, input.plannedSessionsByNow - input.completedThisWeek)
      : 0;
  if (missed > 0) {
    return receipt({
      decision: { kind: 'reschedule', missedSessions: missed },
      rationale:
        'A planned session was missed. The plan moves the work forward; it does not add punitive catch-up volume.',
      signalFreshness,
      evidenceIds: ADHERENCE_EVIDENCE,
      before: plan,
      after: `${missed} session(s) carried forward inside this week's plan.`,
      reviewPoint: 'End of the current week',
      nextAction: 'Train your next planned session on the next available day.',
    });
  }

  // Body-weight trajectory drift needs multiple fresh points over a sustained
  // window. A single noisy datum or an off-target day changes nothing, and no
  // nutrition prescription exists without an approved nutrition engine.
  if (input.trajectory && trajectoryRate !== null && trajectoryFresh === 'fresh') {
    const band = input.trajectory.targetRateKgPerWeek;
    if (trajectoryRate < band.min || trajectoryRate > band.max) {
      return receipt({
        decision: {
          kind: 'ask_question',
          question:
            'Your weight trend is moving away from target. Has your intake, activity, or schedule changed recently?',
        },
        rationale:
          'The trend deviated from the target band across a sustained window of fresh data. One clarifying question precedes any change; the controller does not prescribe nutrition numbers.',
        signalFreshness,
        evidenceIds: TRAJECTORY_EVIDENCE,
        before: plan,
        after: 'Plan unchanged pending your answer.',
        reviewPoint: 'At your reply or the weekly checkpoint',
        nextAction: 'Answer the one question above.',
      });
    }
  }

  const weekComplete = input.completedThisWeek >= input.setup.sessionsPerWeek;
  const performing = orderedFeedback[0]?.performance === 'up';
  if (weekComplete && performing) {
    return receipt({
      decision: { kind: 'hold', optionalBurdenReduction: true },
      rationale:
        'The plan is ahead of schedule and performance is rising. Being ahead never means pushing harder; holding (or optionally reducing) the dose preserves goal probability.',
      signalFreshness,
      evidenceIds: HOLD_EVIDENCE,
      before: plan,
      after: 'Plan unchanged; reduced burden remains available on request.',
      reviewPoint: 'Start of next week',
      nextAction: "You're ahead of plan. Rest — the next sessions unlock next week.",
    });
  }

  return receipt({
    decision: { kind: 'hold', optionalBurdenReduction: false },
    rationale: recentContradiction
      ? 'Recent check-ins conflict, so recovery evidence is ambiguous. No forced change.'
      : 'Trajectory matches plan and no disruption is active.',
    signalFreshness,
    evidenceIds: HOLD_EVIDENCE,
    before: plan,
    after: 'Plan unchanged.',
    reviewPoint: 'Next scheduled session',
    nextAction: ON_TRACK,
  });
}

export type SteeringRequest =
  | { type: 'rest_today' }
  | { type: 'reduce_today_volume' }
  | { type: 'add_extra_session' }
  | { type: 'increase_weekly_volume' };

export type SteeringOutcome =
  | { applied: true; decision: ControllerDecision; reason: string }
  | { applied: false; reason: string };

/**
 * User steering is honored inside reviewed policy bounds. Interventions that
 * would escalate dose beyond the deterministic engine's evidence are caught
 * and rejected; evidence and durable preferences are never erased.
 */
export function applySteering(request: SteeringRequest): SteeringOutcome {
  switch (request.type) {
    case 'rest_today':
      return {
        applied: true,
        decision: { kind: 'reschedule', missedSessions: 0 },
        reason: 'Rest day honored. The planned session moves to the next available day.',
      };
    case 'reduce_today_volume':
      return {
        applied: true,
        decision: { kind: 'adjust_training', adjustment: 'shorten_session' },
        reason: "Today's session is shortened to one set per movement.",
      };
    case 'add_extra_session':
      return {
        applied: false,
        reason:
          'Weekly frequency is fixed by the enrolled program. Extra sessions are outside bounded policy; recovery evidence does not support escalation.',
      };
    case 'increase_weekly_volume':
      return {
        applied: false,
        reason:
          'Volume changes come only from engine progression evidence, not requests. The current dose is preserved.',
      };
  }
}
