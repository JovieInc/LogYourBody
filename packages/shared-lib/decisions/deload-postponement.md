# Deload postponement (LYB-267)

Recorded November 1, 2026. Parent: LYB-173. **Accepted default** under the
issue's “ships if unanswered” instruction. The [decision record](deload-postponement.json)
owns the bounds and exact receipt copy. This records product authorization;
it does not claim separate clinical approval or implement a training change.

Allow **one postponement, up to seven calendar days**, for an optional
engine-proposed deload. Cap volume at the saved current engine-authorized level.
Existing pain/symptom pauses, reactive reductions, planned deload boundaries and
coaching exclusions remain authoritative. A second request requires a short
fatigue check-in and engine review before proceeding, without a second automatic
extension. If the proposal remains supported, hold the line at the saved date.
An expired postponement cannot authorize continued unchanged training or silently
accept a plan change. The user remains free to decline or stop.

The seven-day maximum runs from the **original proposed deload start date** in
the saved plan timezone. Save an explicit chosen date within that window; never
silently clamp an out-of-range request or restart the clock on another request.
The allowance follows the unresolved recommendation within its block, across
new proposal IDs and devices. Only an explicit engine resolution closes it.

After a successful saved postponement, say:

> Deload postponed to Mar 12; volume capped at current level.

Mar 12 is a synthetic example of the committed date. For a second request, say:

> Before reviewing this deload again, check in on fatigue. Your deload date stays Mar 12; volume remains capped at the saved level.

If review retains the proposal, or the date has arrived, say:

> This deload has already been postponed once. Review the suggested deload before continuing with LYB's plan.

Keep the existing engine explanation and action for stronger safety restrictions.
Receipt details retain the cap, before/after plan state, source observations,
freshness/confidence, engine evidence IDs, next review time and one next action.
No diagnosis, medical clearance or benefit promise is approved.

[LYB-302](home-coaching-card-wording.json) describes an engine decision that the
check-ins do not support a deload. That sentence cannot explain a user's
postponement of a supported proposal. Card dismissal alone changes neither plan.

The bounds are the issue's product default. Bell et al.'s 2023 Delphi study
(DOI `10.1186/s40798-023-00633-0`, PMID `37730925`; published September 21, 2023;
reviewed November 1, 2026) reports expert-coach consensus on deload design. It does
not validate this postponement limit for an individual. Follow the
[evidence standard](../../../docs/product/evidence-and-recommendation-standard.md)
and [brand safety boundary](../../../docs/product/brand-ethos.md#safety-boundary);
neither this decision nor a completed check-in proves that waiting is safe.

## Engine implementation slice

### Slice: Deload postponement

Key: `deload_postponement`. Dependency: accepted LYB-267 decision above.
Status: ready for implementation in one separate reviewable PR. This is a created
repository-local work specification, not a claimed Linear issue or runtime change.

Extend the existing deterministic training engine/controller and guarded revision
path. Start with [controller.ts](../../../apps/web/src/lib/training/controller.ts),
[engine.ts](../../../apps/web/src/lib/training/engine.ts), and the existing
[mutation admission](../../../docs/engineering/training-mutation-admission.md)
and [cycle lifecycle](../../../docs/engineering/training-cycle-lifecycle.md)
contracts. Do not add a parallel engine, generic override API or a new web UI.
The current “or keep the current plan” controller action must become bounded
under this decision when the new path is enabled. Reactive workout reductions
must remain effective even if the optional proposal is postponed.

Acceptance for the engine PR:

- Consume the recorded bounds as a versioned deterministic policy; the model
  may request/explain a decision but cannot set dates, caps, thresholds or doses.
  Reuse existing recovery feedback fields and evidence rules for the short
  fatigue/readiness check-in; add no model-authored numeric fatigue threshold.
- Bind the original recommendation/block, original and chosen dates, saved
  timezone/deadline, volume snapshot, allowance consumed, policy version and
  evidence references to an owned current plan revision. Keep existing account,
  consent, stale-head and atomic-write protections. Persist the decision and
  receipt together; concurrent/retried requests cannot grant a second allowance.
- Enforce the volume cap in actual next-workout generation across the affected
  sessions/muscles and microcycle, including rescheduling and competing revision
  routes. Do not add catch-up work or permit another route to raise the cap.
  Preserve completed logs, active prescriptions and stricter recovery limits.
- On another request, require a current saved check-in before deterministic
  review. No response, conflicting data or missing evidence grants no extension.
  If the deload remains supported, return the limit receipt and a review action.
  An explicit evidence-backed engine withdrawal is a recorded resolution, not a
  second postponement. At the saved deadline, expire the deferral and require
  review; do not auto-apply a declined proposal or keep recommending the expired
  deferred plan. Apply still needs the existing confirmation.
- Return the approved receipts only for their committed state, retaining the
  source observations, uncertainty, cap, before/after, review point and next
  action. Failed/offline/stale writes have no success receipt. A safety stop uses
  its existing explanation. Gate the new path off by default through the existing
  training platform flags; gate-off preserves the current implementation. Plan
  and receipt integration belongs to this engine PR; native presentation consumes
  its output without calculating a prescription.

Required behavior proof in that PR: first postponement at the seven-day boundary;
shorter chosen date; invalid/past date and request beyond seven days refused
without a silent clamp; saved timezone and DST/date rollover; retry/concurrent
request/relaunch with the same receipt and allowance; second request with absent,
stale, conflicting and current check-ins; proposal retained versus withdrawn;
deadline before/at/after; cap on generated workouts after rescheduling and another
revision; pain/symptom pause, reactive reduction and planned deload precedence;
coaching-ineligible user; stale revision, account/consent change and failed save;
gate-off behavior. Assert persisted state and generated work, not copy alone.

Use the existing engine/service and authenticated-route tests and real database
verifier where persistence changes. Any changed native behavior needs the real
native runner and coverage receipts. Tests in this decision PR validate the
decision artifact only. Full LYB-173 behavior and real-device TestFlight evidence
stay with the parent; no runtime safety or installed-build evidence is claimed here.
