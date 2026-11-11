# Native dated-outcome entry (LYB-341)

The default-off `dated_outcome_v1` Platform gate selects the native entry.
`LaunchPromiseCopy` remains the single copy table. Its gated native sentence is
the exact [LYB-273 adopted decision](https://linear.app/jovie/issue/LYB-273):

> Pick a date. We build the plan backward from it and adjust every week.

The existing sign-in surfaces show it before requesting measurements. After
authentication, the existing `bodyScoreIntro` surface offers one path to the
shared outcome/date editor. Gate-off copy, onboarding, profile completion and
goal editing retain their existing paths. Feature-gate changes refresh entry
and sign-in presentation. There is no new primary surface or navigation mode.

The gated first run and contextual settings/timeline editor use
`RealtimeSyncManager.shared.datedOutcomeStore`. A Save supplies the entire
outcome/date/constraints value. Availability text, travel and maintenance edits
are resolved off-main, then validated and committed on the journal's background
context. Other existing constraints remain intact. Invalid text does not fall
back to the accepted value. The opening revision prevents a stale editor from
overwriting a newer local save. Unchanged Save emits no request; one changed
Save commits one request with the whole edit. No date or planner baseline is
rewritten by the editor.

Back, Cancel and sheet dismissal return to the retained saved outcome. Manual
entry reuses `AddEntrySheet` with a frozen account session. Apple Health, photos,
DEXA, GLP-1 disclosure and a complete profile are not prerequisites for neutral
tracking. Profile completion is also optional for gated logging deep links;
authentication, completed first run and subscription checks remain enforced.
This does not establish eligibility for a plan.

First-run recovery reuses `DatedTimelineProjector`, the feasibility classifier
and backward planner off-main. Expiry, unsafe/impossible dates, no data and
offline recovery keep their existing distinctions and destinations. The gated
admission adapter additionally requires positively established eligibility and
applies LYB-273's unrounded rejection formula using the latest accepted,
comparable weight and elapsed UTC weeks. More than 1% in either direction is
rejected; passing that check is neither a safety certificate nor an outcome
guarantee. Missing complete policy cannot be filled by that ceiling.

Pending outcomes are labeled as saved on this device. Failed sync offers retry
with the same journal request UUID. A 409 retains the device value and exposes
explicit account comparison. Reviewing does not mutate either value. Choosing
the account outcome explicitly discards the device edit, checks the opening
revision again and creates no recompute request. A local editor conflict can
discard its unsaved draft without acknowledging the newer pending edit. All
loads, saves, comparisons and reconciliation reject replaced account sessions.

## Source reconciliation and release boundary

LYB-273, LYB-286 and LYB-287 were read directly from Linear on 2026-11-02.
Current Jovie main still has launch-contract document blob
`4806bd4fd856e3fca55bc38a4f5ae8ee39759213`, with the older native promise.
Its JSON has no numeric feasibility policy. The existing LYB-286 source guard
now also requires the adopted gated sentence while preserving legacy strings.
The LYB-287 rule table remains unchanged: no efficacy/safety claims; optional
DEXA/GLP-1; user-controlled date recovery.

The Jovie owner must reconcile the upstream promise and supply complete reviewed
absolute bounds, metric policies, freshness/provenance and eligibility checks
before production admission or rollout. Production callers supply no invented
bounds and no affirmative eligibility, so no plan can be admitted. Policy files,
immutable fixtures, certification scripts and CI gates are unchanged.

## Tests and receipts

New methods live in the existing `DatedOutcomeStoreTests`, `LaunchJourneyTests`
and `LogYourBodyUITests` targets. Unit selects the service tests. Launch Quality
selects the first-launch/cancel/back/date-edit/manual-baseline, gate-off,
timeline manual baseline and offline retry/account-isolation cases independently.
Each has its own XCTest timeout and required passing execution receipt in the
same runner invocation. Calling these cases from the screenshot cases caused
run 42366774177 to exhaust the shared 120-second test allowance. The existing
shared-lib launch-quality evidence guard rejects nested XCTest calls and lost
dated-outcome selectors. The UI fixtures are interaction scaffolding, not installed-build proof.
Same-owner SQLite relaunch is covered by the existing real journal reopen test;
the UI fixture deliberately uses a different account on every app launch.

The LYB-271 bindings and generated manifest include the new methods. Bindings
declare required behavior, not passed XCTest records. Ceiling arithmetic uses
the decision's 100 kg / ten-week examples in both directions, including exactly
1%, above, below and maintenance. Complete test-only bounds isolate rejection
arithmetic; the same cases also assert missing production policy rejects them.
They do not certify production feasibility policy.

Linux host validation: source-pinned Node 22.23.2 / pnpm 10.34.1 root lint,
typecheck, test and product checks; SwiftLint; Swift architecture ratchet;
native project membership; launch UI audit and its 35 behavioral tests. The copy
guard was run with the adopted sentence removed and rejected it, then passed
after restoration. Sandbox subprocess restrictions required running the full
test and product suites outside the sandbox. Linux SwiftLint skips its five
SourceKit-dependent rules.

Xcode is unavailable (`xcodebuild: command not found`). Current exact-head native
execution, named passing native failure cases and same-selector native coverage
nonregression remain unverified. No coverage floor was changed. Installed-build,
device/TestFlight and full certification stay with LYB-183/LYB-289; JOV-6013 is
not closed. The harness owns push and PR operations.

Machine: built packages/shared-lib/src/launch-promise-copy.test.ts
