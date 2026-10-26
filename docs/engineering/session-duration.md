# Derived session duration (LYB-290)

`apps/web/src/lib/training/session-duration.ts` exports the pure engine function
`planSessionDuration`. Pass an existing LYB-107/130 `Session`, the rolling queue's
`NextEligibleSession`, priority muscles, timing estimates, and a marginal-value
signal for each prescribed candidate set. Per-muscle recovery distribution can
supply optional absolute fractional-set budgets and minimum RIR limits. The module
does not estimate personal recovery or generate additional prescriptions.

An unrestricted call omits `timeCapMinutes` (or supplies null). Its returned
`requiredDurationMinutes` is null. There is no required duration choice, default
time budget, or maximum session length. Positive marginal-value signals justify
retained work with `marginal_benefit_retained`, including long sessions. At the
first nonpositive value or fatigue-limited set for an exercise, that set and its
remaining candidate sets are omitted, even when time remains.

The duration receipt contains seconds for warm-up, prescribed set execution,
between-set rest, equipment transitions, and their sum, plus unrounded minutes.
The supplied set estimate covers the whole set, including both sides of a
unilateral movement. Rest is counted between consecutive sets of one exercise;
there is no trailing rest after its final set. A change between consecutive
station/setup IDs incurs the supplied transition cost. Use distinct IDs for
different machines even if both use the same equipment category. Removing an
exercise recomputes transitions. These are scheduling estimates, not measured
duration or physiological rest recommendations.

A time cap removes the lowest-value available final set until the derived total
fits. Equal values remove later exercises first. Canonical exercise IDs, order,
and contiguous set numbers remain intact. One direct touch per productive
priority muscle is retained in the selected exposure, preserving its place in the
rolling frequency without creating another session. A shortened result is
`abbreviated`. If the retained priority touches cannot fit, the result is
`unavailable` with no session and `priority_touches_do_not_fit`; it never silently
exceeds the cap. `omittedPriorityMuscles` also exposes priorities absent from the
supplied work or removed by productivity/recovery limits.

Recovery limits apply before time limits and remain authoritative even with ample
time. Fractional budgets include indirect compound contributions. An effort limit
raises RIR only for work contributing to that muscle and holds progression.
Stored alternatives cannot restore removed sets or a lower RIR. Absolute budgets
and RIR bounds avoid repeated proportional cuts. Reapplying the same cap to the
returned prescription produces the same set list. Constraints removed on a later
call should be evaluated against the original prescription to recover its work.

The returned eligibility receipt is unchanged. Neither derived duration, time
caps, actual duration, nor recovery trimming certifies readiness. Safety stops and
paused prescriptions remain unavailable. Optional `actualDurationMinutes` is
returned separately, with `actualMinusPlannedMinutes`; it does not recalibrate the
timing estimates. Empty/unavailable results have zero planned duration.

This slice is the engine module and its CI fixtures. It composes the existing
queue and prescription contracts without changing enrollment, onboarding,
delegated planning's legacy time-budget contract, persistence, or native UI.
Callers applying a result must use the existing gated training admission and
revision boundaries; changing a variant requires rerunning duration/recovery
validation with that variant's contributions and timing. No rollout is activated.

Run from the repository root:

```bash
corepack pnpm --filter logyourbody test:watch --watch=false --runInBand --runTestsByPath src/lib/training/session-duration.test.ts src/lib/training/rolling-session.test.ts src/lib/training/engine.test.ts
corepack pnpm lint
corepack pnpm typecheck
corepack pnpm test
```
