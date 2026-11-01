# Adherence offer templates (LYB-293)

LYB-293 authorizes the default outbound copy below if unanswered. This is a
renderer and response-state slice of LYB-174, with fixtures in the required web
Jest suite. It adds no delivery transport, scheduler, plan writer or rollout.

For a stable five-requested/four-achieved proposal, use exactly:

> You've completed four sessions a week for three weeks. Consolidate to four days? You can switch back.

Actions: **Keep 5** / **Use 4**. This request's explicit default governs these
outbound templates; the separate native prompt decision in
[LYB-259](../product/training-frequency-consolidation.md) retains its own copy and
implementation scope. This slice does not implement that native prompt.

For a six-requested/one-achieved capacity-review proposal, use:

> You've completed one session a week. Review what fits your schedule? Your current training volume stays the same.

Actions: **Keep current plan** / **Review capacity**. This offers a capacity
conversation, never a one-session prescription or a volume reduction.

## Renderer contract

[`renderAdherenceOffer`](../../apps/web/src/lib/training/adherence-offers.ts)
consumes the existing rolling detector's `attendanceChoice`, a proposal ID, known
travel status for the evaluated windows, and caller-owned offer state. It does
not reconstruct attendance windows or calculate a schedule. The consolidate copy
requires at least three recorded four-visit windows; capacity review accepts the
detector's repeated one-visit pattern. Other patterns have no approved template.
A single disrupted week produces no payload. Any travel week or unknown travel
status suppresses both templates. Ineligible input does not consume the ID.

Presentation defaults off. A future caller must supply its authorized gate
decision and establish eligibility through the owned detector flow. Consolidation
also requires confirmation that the canonical plan-review path supports reversal;
otherwise its reversible offer is withheld. **Use 4** only requests that review.
Accepted plan edits remain with LYB-164 / LYB-130; logging remains with LYB-123.

Each result contains an outbound payload list, next offer state and an empty
`programDiff`. Payload identity depends only on proposal ID, across template
types. The caller must serialize transitions per user and atomically retain the
next `handledProposalIds` state with its payload before exposing that payload.
Rehydrate this state for retries/restarts; rendering again with the retained state
produces no second payload. No durable adapter or send worker is introduced here.
This state is not the canonical requested cadence or a copy of the plan.

`declineAdherenceOffer` only remembers the proposal ID and returns no payload or
program changes. Decline, dismissal and no response never alter the user's stored
request. Fixtures read back a canonical five-session program after decline.

These templates stay separate from program revision and training MCP records.
The [LYB-281 outbound policy](training-outbound-policy.md) still forbids prose or
delivery instructions on those surfaces. Future delivery integration must retain
that boundary; this module grants no sending authority.
