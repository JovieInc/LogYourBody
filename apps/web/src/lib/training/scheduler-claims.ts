import type { RollingScheduleReview } from './rolling-schedule-schema';
import type { RollingSelectionReason } from './rolling-session';
import type { SessionDurationReason } from './session-duration';
import type { WorkoutSessionEvent } from './types';

/** LYB-292: the only approved sentences for scheduler rationale and plan receipts.
 * Targets remain individualized; frequency distributes work, and neither elapsed
 * time, soreness nor duration certifies recovery. This catalog changes no math.
 * Additional codes require an approved sentence and the catalog contract tests. */
export const SCHEDULER_CLAIMS = Object.freeze({
  first_exposure: 'Start with the first exposure in your approved rotation.',
  next_after_last_completion: 'Continue the rotation from the last recorded completion.',
  skipped_recent_stimulus:
    'Another exposure comes first because recent overlapping work falls within your supplied scheduling window.',
  continuation_context_requires_review:
    'Review the partial workout and its visit identity before continuing its remaining work.',
  use_explicit_continuation_for_existing_visit:
    'Continuing this recorded visit requires an explicit continuation of its partial workout.',
  additional_visit_requires_review:
    'Review the distribution of your individualized target before adding a visit beyond your agreed frequency.',
  applied_recovery_reduction:
    'The applied recovery review reduces your remaining approved work for this trial.',
  no_feasible_work_at_this_opportunity:
    'No remaining approved work fits this opportunity under the current constraints.',
  requires_reviewed_move_reduction_or_rest:
    'Review moving or reducing the remaining work, or resting, within your individualized plan.',
  remaining_work_is_not_catch_up_debt:
    'Remaining work calls for a plan review rather than extra work to repay missed visits.',
  conditional_not_measured:
    'This proposed schedule is conditional on your current response and does not measure recovery.',
  readiness_is_dose_and_context_dependent:
    'Readiness remains conditional on the proposed dose, completed work, and your current context.',
  warmup_and_symptoms_require_reassessment:
    'Reassess warm-up performance and symptoms because soreness alone cannot establish recovery.',
  unlogged_workout: 'Unlogged work leaves uncertainty about the training already completed.',
  stale_or_future_observation:
    'Some observations are stale or future-dated, so current readiness remains uncertain.',
  conflicting_observations:
    'Conflicting observations leave readiness uncertain and require review before changing the plan.',
  direct_and_overlapping_completed_work_requires_review:
    'Review both direct and overlapping completed work when considering the proposed dose.',
  no_completed_work:
    'No completed work is recorded in this snapshot, so training history cannot establish readiness.',
  earlier_proposed_work_requires_reassessment_after_completion:
    'Reassess later proposed work after the earlier work is completed and its response is known.',
  offer_consolidation:
    'Your recorded attendance supports reviewing fewer visits as a way to distribute your individualized target.',
  review_capacity:
    'Review how your individualized target can fit your recorded attendance before changing visit frequency.',
  marginal_benefit_retained:
    'Retained sets have positive supplied marginal-benefit signals, and their estimated duration does not certify recovery.',
  marginal_value_exhausted:
    'Further sets for this exercise are omitted where the supplied marginal-benefit signal is no longer positive.',
  fatigue_limit_reached:
    'Further sets for this exercise are omitted where the supplied fatigue signal limits productive work.',
  recovery_limit_applied:
    'The supplied recovery limits constrain retained volume or effort even when more time is available.',
  time_cap_applied:
    'Lower-value work is trimmed to fit your supplied time cap while preserving feasible productive priority touches.',
  priority_touches_do_not_fit:
    'The productive priority touches cannot fit your supplied time cap, so this opportunity needs review.',
  no_productive_sets: 'No productive sets remain available under the current constraints.',
  session_unavailable:
    'This session remains unavailable while its safety stop or execution pause is active.',
  shortened: 'Your requested time budget was applied while preserving already logged work.',
  ended: 'This workout was ended, and only logged work counts as completed training.',
} as const satisfies Record<
  | RollingSelectionReason
  | SessionDurationReason
  | RollingScheduleReview['readiness']
  | NonNullable<RollingScheduleReview['attendanceChoice']>['kind']
  | Extract<WorkoutSessionEvent['kind'], 'shortened' | 'ended'>,
  string
> &
  Record<string, string>);

export type SchedulerClaimCode = keyof typeof SCHEDULER_CLAIMS;

/** Unknown codes cannot become free-form receipt copy or fall back to a claim. */
export function schedulerClaim(reasonCode: string): string {
  if (!Object.prototype.hasOwnProperty.call(SCHEDULER_CLAIMS, reasonCode)) {
    throw new Error(`unapproved_scheduler_claim: ${reasonCode}`);
  }
  return SCHEDULER_CLAIMS[reasonCode as SchedulerClaimCode];
}
