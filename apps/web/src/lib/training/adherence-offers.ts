import type { RollingScheduleReview } from './rolling-schedule-schema';

type AttendanceChoice = NonNullable<RollingScheduleReview['attendanceChoice']>;
type OfferAction = Readonly<{
  id: 'decline' | 'review_consolidation' | 'review_capacity';
  label: string;
}>;
type OfferTemplate = Readonly<{ message: string; actions: readonly OfferAction[] }>;

function template(message: string, actions: OfferAction[]): OfferTemplate {
  return Object.freeze({
    message,
    actions: Object.freeze(actions.map((action) => Object.freeze(action))),
  });
}

/** LYB-293 authorizes these defaults. Actions request review; they never edit a plan. */
export const ADHERENCE_OFFER_TEMPLATES = Object.freeze({
  offer_consolidation: template(
    "You've completed four sessions a week for three weeks. Consolidate to four days? You can switch back.",
    [
      { id: 'decline', label: 'Keep 5' },
      { id: 'review_consolidation', label: 'Use 4' },
    ],
  ),
  review_capacity: template(
    "You've completed one session a week. Review what fits your schedule? Your current training volume stays the same.",
    [
      { id: 'decline', label: 'Keep current plan' },
      { id: 'review_capacity', label: 'Review capacity' },
    ],
  ),
} satisfies Record<AttendanceChoice['kind'], OfferTemplate>);

/** Caller-owned, per-user state. Retain it with the payload atomically before
 * exposing output, and serialize transitions for that user, including retries.
 * No process-local cache, cadence store or delivery transport is created here. */
export type AdherenceOfferState = Readonly<{ handledProposalIds: readonly string[] }>;
export type AdherenceOfferPayload = OfferTemplate &
  Readonly<{
    id: string;
    proposalId: string;
    template: AttendanceChoice['kind'];
  }>;
export type AdherenceOfferResult = {
  state: AdherenceOfferState;
  outbound: readonly AdherenceOfferPayload[];
  programDiff: readonly never[];
};

function handled(state: AdherenceOfferState, proposalId: string): AdherenceOfferState {
  return !proposalId.trim() || state.handledProposalIds.includes(proposalId)
    ? state
    : { handledProposalIds: [...state.handledProposalIds, proposalId] };
}

/** Decline only remembers the proposal; the canonical requested cadence is untouched. */
export function declineAdherenceOffer(
  state: AdherenceOfferState,
  proposalId: string,
): AdherenceOfferResult {
  return { state: handled(state, proposalId), outbound: [], programDiff: [] };
}

/** Render owned detector output only. Complete windows and visit counting belong
 * to the detector. These checks limit the facts each approved template can say.
 * The caller supplies the presentation gate and known travel status for the
 * evaluated windows; missing eligibility suppresses output without consuming an id.
 * Payloads are separate from structured revision/MCP responses (LYB-281). */
export function renderAdherenceOffer(input: {
  proposalId: string;
  choice: RollingScheduleReview['attendanceChoice'];
  state: AdherenceOfferState;
  hasTravelWeek: boolean | null;
  enabled?: boolean;
  canReverseConsolidation?: boolean;
}): AdherenceOfferResult {
  const empty: AdherenceOfferResult = { state: input.state, outbound: [], programDiff: [] };
  const choice = input.choice;
  if (
    input.enabled !== true ||
    input.hasTravelWeek !== false ||
    !input.proposalId.trim() ||
    input.state.handledProposalIds.includes(input.proposalId) ||
    !choice ||
    choice.applied !== false ||
    choice.reversible !== true
  )
    return empty;

  switch (choice.kind) {
    case 'offer_consolidation':
      if (
        input.canReverseConsolidation !== true ||
        choice.requestedVisits !== 5 ||
        choice.suggestedVisits !== 4 ||
        choice.observedVisitsPerWeek.length < 3 ||
        !choice.observedVisitsPerWeek.slice(-3).every((count) => count === 4)
      )
        return empty;
      break;
    case 'review_capacity':
      if (
        choice.requestedVisits !== 6 ||
        choice.suggestedVisits !== null ||
        choice.observedVisitsPerWeek.length < 2 ||
        !choice.observedVisitsPerWeek.every((count) => count === 1)
      )
        return empty;
      break;
    default:
      return empty;
  }

  return {
    state: handled(input.state, input.proposalId),
    outbound: [
      {
        id: `adherence-offer:${encodeURIComponent(input.proposalId)}`,
        proposalId: input.proposalId,
        template: choice.kind,
        ...ADHERENCE_OFFER_TEMPLATES[choice.kind],
      },
    ],
    programDiff: [],
  };
}
