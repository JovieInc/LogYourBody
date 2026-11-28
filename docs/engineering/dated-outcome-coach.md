# Dated-outcome coach (LYB-344)

Machine: extended `DatedTimelineProjector`, `BackwardPlanner`, the existing
owner-scoped outcome journal and `LaunchDirectiveCard`. No new store, policy,
programming engine, notification system or primary destination is introduced.

The existing default-off Platform gate `dated_outcome_v1` controls the entire
integration. Expanding Jovi shows the shared coach directive. An admitted weight
outcome receives the backward planner's single hold/review action, with its
original baseline, reviewed measurement, target/date/constraints, provenance,
rationale, uncertainty and next weekly review. The action button opens the
existing goal-relative Stats destination. No training quantities or training
adjustments are produced by this projection. Numeric training guidance remains
owned by the existing training engine and guarded chat transport, including its
opaque evidence IDs. This slice does not turn body-weight drift into a training
prescription or tell the user that a training adjustment was applied.

The journal stores the action as local metadata alongside the current outcome
revision. All preparation and health-memory checks run inside the existing
projector actor. Encoding and Core Data work use the private context. Publishing
waits for the write to succeed. Revision, baseline, owner, product, refresh and
account-session checks reject stale receipts. Metadata creates no sync edit;
acknowledgement and SQLite reopening retain it. A date/target/constraint edit
invalidates the action and recomputes against the original baseline. Logout
removes access; account deletion uses the existing journal deletion path.

Returning before the weekly review restores the persisted decision and review
time. A due review requires a newer comparable measurement. Without one, the
coach requests a fresh reading, preserving the previous receipt and date without
claiming a change. With one, it compares against the original dated trajectory
and persists the planner's new hold/review decision. Removed or corrected cached
evidence cannot silently restore a prior decision. Foreground/data changes
refresh the projection; one cancellable wake targets the earlier of the next
review and UTC deadline. A missing reading does not start a polling loop.

Every recovery consumes the existing classifier, safe-claim presentation and
recovery destination. Recovery states expose no active prescription or cached
health evidence. Maintenance offers constraint review. Missing/denied/stale or
conflicting readings offer manual entry; HealthKit, photos, DEXA, GLP-1 and
notifications remain optional. The existing `HealthMemoryStore` boundary admits
only matching user/product evidence with measured or engine-derived provenance;
unavailable checks and coach-inferred evidence fail closed.

## Policy and release limits

The policy conflict recorded in `dated-outcome-stats.md` remains unresolved:
LYB-273's adopted sentence differs from the LYB-286 canonical table, and the
recorded Jovie contract supplies no numeric feasibility bounds. This integration
consumes that table and LYB-287's no-claim recovery behavior without replacing
promise strings, selecting rates, choosing target bounds or changing upstream
policy. The existing adopted rate ceiling remains an outer rejection check only.
Production inputs still supply no complete policy, so the coach cannot admit an
active plan. Reconciliation and complete eligibility/policy wiring are release
prerequisites. Passing arithmetic establishes neither safety nor an outcome.

An attempted upstream read through the GitHub Contents API was rejected by
automatic approval review because this run prohibits that API. No upstream
policy was fetched or changed. Current reconciliation remains unverified.

## Verification and remaining evidence

Five new `DatedOutcomeStatsTests` cases cover first action/restore, weekly
on-track/behind/ahead hold/review, a weekly evidence gap, date-edit/retry and
unavailable policy/planner/foreign memory. The existing ten-state test also
asserts the coach presentation and recovery-only states. A new
`DatedOutcomeStoreTests` case covers SQLite reopen, acknowledgement, unchanged
sync requests, failed-write rollback, date invalidation, stale revision rejection
and account isolation.
Both suites are already in the real native unit target and Unit selector.

Each existing, independently selected `testDatedStats<State>HasOneReachableRecovery`
UI case also opens the mounted Jovi surface and exercises its single recovery.
The arithmetic fixture has no persisted outcome revision; its ready arithmetic
therefore verifies unavailable-plan recovery, not a fabricated active receipt.
LYB-271 bindings are updated with these service paths; manifest bindings and
synthetic arithmetic are requirements/source evidence, not installed-build proof.

Host validation uses Node 22.23.2, pnpm 10.34.1 and scoped strict SwiftLint.
The pure Swift 6.0.3/Swift 5-mode harness compiles current model/planner/projector
sources and the existing provenance/editorial declarations, stubs unused
Platform gate access closed, and omits the unrelated CryptoKit identity helper
from its Linux-only model copy. Its fixture resource uses `Bundle.module` for
SwiftPM. It supplies no Core Data, SwiftUI, native coverage or installed receipts.

Passed on this host: root `pnpm lint`, `pnpm typecheck`, `pnpm test` (eight
Turbo tasks), `pnpm product:check`, scoped strict SwiftLint, the Swift architecture
ratchet, native project membership, launch UI static audit, repository source
parity and the existing manifest suite (11 cases). The pnpm shim pins 10.34.1
for nested commands. Test/registry/manifest subprocesses required execution
outside sandbox filesystem limits. Linux SwiftLint skips five SourceKit rules.
The pure Swift harness passed 44 cases, including the five new coach cases.
Disabling the weekly-new-reading check in a temporary source copy failed the
freshness regression with five assertions; restored source passed again. These
are local source/logic results, not native execution or coverage receipts.

The actual native command was attempted with `LogYourBodyTiers`, `Unit`, the two
changed suites and coverage enabled; this Linux host has no `xcodebuild`.
Current exact-head native execution, named native failure-case passes,
same-selector coverage nonregression and the real saved-action UI journey remain
unverified. They must run on the existing native runner after policy integration.
No immutable fixture, certification script, coverage floor or CI gate was changed.
Installed-build, device/TestFlight and full parent closeout stay with
LYB-183/LYB-289. This slice does not close JOV-6013.

GBrain query, write and same-slug readback were attempted at
`engineering/lyb-344-dated-outcome-coach`; the configured endpoint at
`127.0.0.1:7801` was unreachable. Durable write and readback remain unconfirmed.
