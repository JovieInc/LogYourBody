# Dated outcome timeline (LYB-342)

The existing photo timeline consumes the saved `DatedOutcome` under the
existing default-off Platform gate `dated_outcome_v1`. The existing timeline,
Stats and coach navigation stays in place. The saved target is explicitly
user-selected and always shows its saved date; tapping it opens the existing
outcome editor. This slice adds no planning quantities or promise strings.

`DatedTimelineProjector` prepares recorded values, canonical-unit comparisons,
measurement dates, import provenance and one recovery destination on an actor.
The timeline reads the prepared snapshot rather than fetching the journal or
classifying the whole measurement collection while rendering. The new journal
presentation APIs suspend while its background context fetches, validates,
encodes and saves. Both presentation APIs reject stale account sessions.

Manual entry uses `AddEntrySheet`: weight for a weight baseline, body fat for a
body-fat baseline, and the existing weight/body-fat/profile inputs for derived
FFMI. DEXA, GLP-1 disclosure, Apple Health and progress photos are optional.
An empty Health read is not labeled a permission denial. Cancelling an optional
photo import returns to the retained outcome; manual entry remains available
without an import or network connection. An empty photo stage has one add-photo
action. Existing photo attachment, picker and import behavior remains shared.

Recorded measurement dates establish freshness, never creation/import times.
Excluded, future, foreign-account and unknown-unit values cannot establish a
comparable baseline. Visual/body-scan estimates retain their estimate captions;
unknown methods and photo-derived values cannot establish measured state.
FFMI retains its derived label. A conflicting timestamp offers manual entry.
Expiry opens the shared editor with the original date. Maintenance and safety
use the shared classifier/planner; no branch extends a date.

Snapshots, in-flight loads, editors, photo attachments and logger actions are
bound to the account session generation. Switching accounts clears transient
presentations; a late result cannot publish the prior account's goal or action.
History remains hidden until its owner and selected entry match the active
session. Existing hidden-surface/deep-link recovery is unchanged.

The reused logging and photo sheets freeze the opening account session in
presentation state. The shared `NativeSheetPresentationPolicy` rejects delayed
actions after account replacement or a new generation of the same account;
late logger callbacks cannot publish into the replacement session. Existing
callers keep their behavior through the optional, default-unbound parameter.

## Policy reconciliation remains required before rollout

The repository's pinned upstream v1 policy supplies no numerical feasibility
thresholds, and its current native promise differs from the LYB-273 decision
referenced by this issue. LYB-273, LYB-286 and LYB-287 could not be fetched from
Linear/GitHub on this implementation host. No rates, absolute target limits,
freshness windows, policy fixtures or replacement promises were chosen here.
Missing/incomplete policy cannot admit a plan. Passing a rate check would not
establish runtime safety or guarantee an outcome. Reconcile the owner-approved
sources before enabling the gate or releasing this journey.

## Native test bindings and evidence boundary

`DatedTimelineTests` is in the existing app unit-test target and the real Unit
selector. Named cases cover all ten timeline route states, denied/interrupted
optional inputs, offline manual entry, incomplete policy, historical provenance,
conflicts, expiry, optional-input independence and manual FFMI inputs.
`DatedOutcomeStoreTests` adds presentation persistence/reopen, stale-editor
rejection and delayed-read isolation to its existing storage tests.

`LogYourBodyUITests/testDatedTimelineManualBaselineAndInterruptedPhotoReturn()`
and `testDatedTimelineSwipeProvenanceOfflineRetryAndAccountIsolation()` exercise
the existing editor, logger, photo cancellation, scrubber and offline retry.
Their flows also run from the already selected
`testLaunchQualityGateCapturesTimelineSurfaces()` path. They use DEBUG fixtures;
the existing fixture creates a different account on each launch, so that UI
relaunch checks isolation. Same-owner relaunch is tested against the real
journal in the native service test, without reseeding storage.

The input bindings are `scripts/fixtures/lyb-launch-route-bindings.json`.
Regenerate the manifest with the existing producer:

```sh
node scripts/lyb-launch-manifest.mjs scripts/fixtures/lyb-launch-route-bindings.json
```

These bindings describe executable tests, not passing native receipts. The
Linux implementation host has no Xcode, simulator or native coverage tooling.
Current exact-head native execution, named passing failure cases and same-selector
coverage nonregression therefore remain unverified and must be supplied by the
real native CI runner. Installed-build, device/TestFlight and parent certification
remain with LYB-183/LYB-289. This slice does not close JOV-6013.

Host validation completed with Node 22.23.2 and source-pinned pnpm 10.34.1:
root `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm product:check`, scoped
SwiftLint (`--strict --no-cache`), the Swift architecture ratchet, native project
membership and launch UI regression audits. Sandbox subprocess restrictions
required elevation for the repository and product test suites. SwiftLint's
SourceKit-dependent rules were unavailable on Linux. An attempted
`xcodebuild ... build-for-testing` returned `command not found`; it is not a
native passing result. No native coverage baseline was changed.

GBrain query, write to `lyb-342-dated-outcome-timeline`, and readback all failed
because the configured local endpoint at `127.0.0.1:7801` was unreachable.
The durable write and readback are therefore both unconfirmed; this document
retains the findings for the next run.
