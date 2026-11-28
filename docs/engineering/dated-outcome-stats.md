# Goal-relative stats (LYB-343)

The existing Stats destination and Home/Progress navigation consume the saved
outcome through `DatedTimelineProjector` when the existing default-off Platform
gate `dated_outcome_v1` is enabled. Gate off keeps the previous metrics/Progress
surface. There is no new score model, coach layout, navigation or prescription.

Machine: extended `apps/ios/LogYourBody/Services/DatedTimeline.swift` and the
existing journal, planner, classifier, directive and outcome editor.

The actor prepares recorded values, estimate captions, the user-selected target,
saved UTC deadline, remaining elapsed days and planner drift. Drift is evaluated
at the accepted measurement timestamp, never extrapolated to the current clock.
The stats surface exposes no score, synthetic trend or recovery-state trajectory.
FFMI keeps its derived label; visual, scan and other estimates cannot establish
a measured baseline. Excluded, future, foreign-account and unknown-unit records
remain excluded through the shared timeline preparation.

The existing classifier's five results feed the ten manifest route states.
Stats presents one contextual recovery through `LaunchDirectiveCard`: manual
entry for missing/denied/stale/conflicting measurements, retry for offline data,
and user-controlled constraint review for rejected targets/dates or unavailable
checks. `ok` conveys no safety or result claim. `impossible` declines the current
constraint without claiming physiological impossibility. Expiry takes precedence
over missing policy, denial, offline and maintenance. The shared editor retains
the date, supports cancellation and an explicitly selected maintenance interval,
and never clamps the target or extends the date. Its additional controls appear
only for the dated-outcome caller.

The original comparable weight baseline is retained as local metadata in the
existing owner-scoped journal payload. Acknowledgement, date/target edits, remote
updates in the same metric and relaunch retain it. Changing metric clears it.
A new unambiguous reading resolves a latest-timestamp conflict; older conflicts
do not mask that recovery. Backfilled history cannot replace the baseline; removing/excluding the baseline prevents
plan admission instead of rebasing. Metadata creates no sync edit or recompute
request and does not enter `DatedOutcomeEdit`'s API payload. No Core Data model
or server schema changes. All metadata encoding, fetches and saves run on the
existing private context. Existing revision/session checks reject stale writes.

Accepted measurements, date edits, sync changes, account changes and foreground
return refresh the projection. The current refresh task also wakes once at the
saved UTC deadline so expiry does not depend on the user's local midnight.
Cancellation and account-session checks protect that delayed refresh.

## Policy sources and rollout prerequisites

Readback from Linear on 2026-11-02 verified LYB-273's adopted decision,
updated 2026-10-30, and the LYB-286/287 dependency records. The classifier exposes
the adopted outer weight-rate check:
`100 * abs(target - latestAcceptedWeight) / (latestAcceptedWeight * elapsedWeeks)`.
Values above 1% are rejected for loss and gain, without rounding, compounding,
changing the baseline, or changing the target/date. Exactly 1% passes only this
check. The projector applies it only after the existing policy, target,
availability, provenance/freshness and planner checks have allowed a ready or
maintenance result. It supplies no missing target bounds or other-metric policy.

Jovie main was read at `2fb926dfb968f29312d9ed7ae3a1fb7724276912`:
[launch contract](https://github.com/JovieInc/Jovie/blob/2fb926dfb968f29312d9ed7ae3a1fb7724276912/docs/product/lyb-launch-contract.md)
and [fixture](https://github.com/JovieInc/Jovie/blob/2fb926dfb968f29312d9ed7ae3a1fb7724276912/scripts/fixtures/lyb-launch-contract.json).
They still contain no numeric feasibility bounds. LYB-273's native sentence is
“Pick a date. We build the plan backward from it and adjust every week.”;
LYB-286's current canonical table still uses the older pinned contract copy.
This slice consumes that table and its non-guarantee framing without forking
promise strings or changing Jovie-owned sources. Reconciliation belongs with
the owner and LYB-341, which was still Todo on readback. Complete policy and
eligibility integration must precede production admission. Missing/incomplete
bounds remain closed, including maintenance and requests at the ceiling.
Passing any arithmetic check establishes neither runtime safety nor an outcome.

## Test bindings and evidence

`DatedOutcomeStatsTests` is registered in the existing unit target and is not
excluded by the real Unit plan. Its nine named cases cover every stats state,
recorded/estimated/target/time/drift separation, insufficient evidence, canonical
loss/gain ceiling examples, all missing bounds, unavailable checks, target
bounds, expiry, baseline preservation, date edits and account replacement.
`DatedOutcomeStoreTests` adds baseline reopen/acknowledgement/edit persistence,
wire isolation, stale revision and account checks.

The existing UI target gives each of the ten manifest states its own
`testDatedStats<State>HasOneReachableRecovery` XCTest case using the shared
`assertDatedStatsRecovery` helper. The real editor, journal, logger, expiry,
optional-photo cancellation and account-isolation journeys are also selected
independently by `scripts/ios/launch-quality-audit.sh`. Every selected case must
produce its own passing execution receipt; none run inside another test method.
The existing shared-lib evidence suite rejects nested test calls, missing state
cases and omitted selectors before using the native runner.

CI run `42356725053` exceeded the two-minute test allowance while the old
Timeline wrapper was still calling the recovery-state loop. Its subsequent
termination error was a timeout symptom. The repair retains the per-test and
outer step limits. The aggregate UI command budget grows from 25 to 30 minutes
for the complete matrix: the failed run already spent 24m15s in that command
with most of the matrix still unexecuted. Native execution on the repaired head
remains required; source checks cannot prove runtime or coverage.

Repair validation on 2026-11-07: root `pnpm lint`, `pnpm typecheck` and
`pnpm test` passed using the pinned toolchain. Both new source guards reject
the immutable original PR sources and pass with the repair. The existing native
evidence suite executed its 34 behavior cases. Scoped strict SwiftLint found
no violations (the five SourceKit rules remain unavailable on Linux); the
architecture ratchet, launch UI static audit, correction coverage, manifest
generation equality, shell syntax and documentation parity checks also passed.
The native XCTest attempt could not run because this host has no `xcodebuild`.
GBrain write and same-slug readback succeeded outside the network sandbox at
`engineering/lyb-343-launch-quality-case-budgets` (page 77662).

Original implementation validation (2026-11-02):

- Root `pnpm lint` and `pnpm typecheck` passed through Turbo cache. Root
  `pnpm test` passed after retrying outside sandbox subprocess restrictions:
  eight tasks succeeded; shared-lib executed 436 Vitest and 141 Node cases.
- Strict SwiftLint, Swift parsing, the architecture ratchet, native project
  membership and launch UI static audit were run. Linux SwiftLint omits five
  SourceKit-dependent rules; the native runner must run the full lint toolchain.
- An isolated Swift 6.0.3 / Swift 5 language-mode harness executed 39 XCTest
  cases: nine stats, eleven classifier and nineteen planner cases. It compiles
  the actual pure service/model sources and extracted existing provenance and
  editorial declarations. Only unused Platform gate access is stubbed closed;
  the unrelated CryptoKit identity method is omitted from the Linux model copy.
  This is projection/arithmetic evidence, not an iOS or Core Data result. Two temporary
  mutations (rejecting exactly 1%, and ignoring the stored baseline) failed their
  regression assertions; restored source passed again.

The scoped native `xcodebuild ... -testPlan Unit -only-testing:LogYourBodyTests/DatedOutcomeStatsTests
-only-testing:LogYourBodyTests/DatedOutcomeStoreTests -enableCodeCoverage YES test`
attempt failed because `xcodebuild` is unavailable. Current exact-head native UI,
Core Data execution, named native passing cases and same-selector coverage
nonregression remain unverified. No coverage floor or CI gate changed. Synthetic
test bounds do not establish production policy. Installed-build, device/TestFlight
and parent certification remain LYB-183/LYB-289; this does not close JOV-6013.

GBrain query, write and same-slug readback were attempted for
`engineering/lyb-343-goal-relative-stats`. The configured local endpoint at
`127.0.0.1:7801` was unavailable; both durable write and readback remain unconfirmed.
