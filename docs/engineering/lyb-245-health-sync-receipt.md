# Apple Health sync caption and weight receipt (LYB-245)

Decision: implement the issue's supplied default under its explicit “ships if
unanswered” instruction. This records default adoption, not a separate claim of
Tim's visual approval. LYB-171 owns real-device and TestFlight evidence.

On Home V2, a neutral caption sits immediately below the hero's FFMI/weight
summary and above Steps. It uses `HomeV2Tokens` typography, spacing and colors,
and `JovieTokens` hit targets and subtle motion duration.

| State model value | Caption                          |
| ----------------- | -------------------------------- |
| checking          | Checking Apple Health…           |
| updated           | Updated from Apple Health, 9:41  |
| unavailable       | Apple Health update unavailable  |
| permissionNeeded  | Apple Health access needed       |
| offline           | Offline · showing saved readings |

The updated timestamp comes from `HealthSyncStateReducer.lastSuccessfulSync`,
not the cloud sync clock. Time follows the device's locale and time zone,
including AM/PM where appropriate. A missing timestamp omits the clock.
Permission state stays passive; rendering it never requests access or retries.

The inline receipt directly below the caption reads
“New weight from Apple Health · Mar 3, 9:41 · 82.4 kg”. It uses the measurement's
date/time and the selected kg/lb unit. It disappears six seconds after the
arrival is observed, or immediately on tap. The transition is a subtle opacity
change; Reduce Motion disables animation. There is no push notification.

Tapping opens a native Recent readings sheet with up to 20 Apple Health weight
readings. A late-arriving reading outside the latest 20 is included first while
its receipt is active. The caption remains tappable after the receipt disappears,
so the destination is accessible without a timed interaction. The sheet offers
Edit, Exclude, and Undo last change through the existing
`MetricCorrectionService`; it never writes to Apple Health or deletes the source
reading. Undo is retained for the last successful change in this dashboard
session. Failed saves retain that undo receipt and show an inline error.

The new surface is behind `health_sync_receipt_v1`, evaluated through the
analytics platform port and off when unassigned. Edit/exclude also respect the
existing `imported_metric_corrections` gate. Enable both gates for staff
acceptance. Undo remains available if the correction gate is disabled after a
successful change, matching the service's contract.

Collection filtering, sorting, identity comparison and provenance parsing run
in `HealthReadingObserver`, away from the main actor. Initial cached history,
duplicates, foreign accounts, invalid/missing weights, excluded readings and
manual corrections do not create receipts. Identity includes the Health sample
ID and original measurement, so a new sample can replace a legacy daily row.
Whole-second import timestamps are respected. A repeated publication never
extends the receipt lifetime. Account lifetime changes clear visible data,
pending undo, errors and the receipt; stale preparations and save results cannot
repopulate the UI.

`HealthSyncPresentationTests` is included in the existing native test target
and is not skipped by the Unit test plan. It freezes copy for every state,
checks kg/lb and measurement-time formatting, and attaches native render
snapshots for all five states with/without the receipt at 320-point width in
regular and accessibility text sizes. These are xcresult image attachments,
not pixel-golden comparisons; the repository has no pixel snapshot framework.
Behavior cases cover arrival eligibility, duplicate suppression, legacy row
replacement, same-value sample identity, account changes, the six-second timer,
tap dismissal, save failure and undo.

Local verification used Node 22.23.2 and Corepack's pinned pnpm 10.34.1:

- `corepack pnpm lint` and `corepack pnpm typecheck` passed.
- `corepack pnpm test` passed with child-process execution available. The first
  sandboxed run failed on `spawnSync EPERM` in existing process-based tests.
- `pnpm product:check` passed with pinned pnpm and child-process execution
  available.
- `node scripts/ios/swift-arch/guard.mjs`,
  `python3 scripts/ios/test_training_rest_project.py`, and
  `node scripts/check-vendor-boundaries.js` passed.
- Scoped `swiftlint lint --strict --no-cache --config apps/ios/.swiftlint.yml`
  passed. This Linux SwiftLint skips five SourceKit-dependent rules.
- Swift 6.0.3 parsed the seven changed Swift files successfully. The date/time
  format style was also executed with the fixed snapshot locale and time zone.
- A supplemental Swift typecheck of the presentation store and real sync
  reducer passed with temporary stubs for platform/domain dependencies. This
  does not validate the native app integration.

Xcode is unavailable on this host. The native Unit run, render snapshot review
and native coverage remain unverified and must pass on the repository's real
native runner before rollout. No TestFlight or release evidence is claimed.

GBrain query, write to `logyourbody-lyb-245-health-sync-receipt`, and readback of
that slug all failed to connect to `127.0.0.1:7801`. Neither remote persistence
nor readback was verified; this document retains the decision locally.

## PR #1679 repair handoff

Mission: preserve LYB-245 while making the branch mergeable through existing gates.
Audience: the lanes harness and repository reviewers.

Merged `origin/main` at `3f3f05bcd` without rebasing. Rebuilt the conflicted source
map from staged inputs and refreshed only the diagnostic workflow's reviewed
project digest for the merged Xcode graph. Moved the recent-readings sheet content
and metrics callback into existing dashboard extensions to retain the unchanged
800-line source baseline. Copy, placement, feature gates and native tests remain.

Extended `scripts/resolve-repository-docs.py` to refuse unresolved conflict markers
in staged source inputs before generating the map. Six real-Git regressions fail
before the change and pass afterward; the two existing required merge-tooling
suites pass all 105 tests. Diagnostic runner-routing tests pass all 65 cases.
Root `corepack pnpm lint`, `corepack pnpm typecheck`, `corepack pnpm test`, pinned
`pnpm product:check`, the Swift architecture guard, vendor-boundary check,
`test_training_rest_project.py`, source-map parity and its 10 Python tests pass.
Scoped strict SwiftLint passes for the three extracted dashboard files, with the
same five unavailable SourceKit rules. Both-parent correction coverage passes
at 191/191 mechanized rules. Native execution and coverage still require macOS.

Tently check `124772519463` reports an unreachable AI provider, with no code
finding. It has no Actions run; `gh run view --log-failed` returns 404. A new
harness push must rerun the external review; no check was bypassed.

The harness owns pushing and PR edits. Add exactly one machine declaration to
the PR body: `Machine: built scripts/resolve-repository-docs.py`.
Intent-eval: n/a - mechanical merge repair and behavior-preserving extraction.
GBrain write to `logyourbody-pr1679-merge-repair` and readback both failed to
connect to `127.0.0.1:7801`; persistence and readback remain unverified.
