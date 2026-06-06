# JOV-2860 Weight Logging UX Evidence

Date: 2026-06-06
Branch: `codex/jov-2860-weight-logging-ux`

## Scope

- Kept `PaidWeightLoggerMVPView` as the paid MVP route.
- Added a keyboard toolbar and bottom save bar so saving remains reachable with the decimal keyboard open.
- Added inline invalid-weight copy before submission.
- Replaced raw sync copy such as `Pending` with user-facing copy:
  - `Sync queued`
  - `Saved offline`
  - `Sync needs retry`
- Preserved the local-first Core Data save through `saveBodyMetricsAndWait(..., markAsSynced: false)` and the existing `RealtimeSyncManager.syncIfNeeded()` trigger.
- Added a debug-only `-lybUITestPaidMVPFixture` launch argument for UI smoke coverage. The fixture is compiled under `#if DEBUG` and does not exist in release builds.

## Visual Evidence

- Keyboard-open save path: `docs/audits/jov-2860/keyboard-open-save-bar.jpg`
  - Shows `182.4 lbs` typed with the keyboard open.
  - Shows both the in-card save button and bottom save bar reachable above the keyboard area.
- Post-save state: `docs/audits/jov-2860/post-save-recent-history.jpg`
  - Shows `Saved locally. Sync queued.`
  - Shows `1 saved`.
  - Shows recent history updated with `182.4 lbs`.

## Local Validation

- `swiftlint lint --strict`
  - Result: passed with `0 violations, 0 serious in 256 files`.
- XcodeBuildMCP `build_run_sim` on iPhone 17 Pro iOS 26.5 with `-lybUITestPaidMVPFixture`
  - Result: succeeded.
  - Build log: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/logs/build_run_sim_2026-06-06T23-41-49-569Z_pid45897_adfa724e.log`
- XcodeBuildMCP focused `test_sim`
  - Tool wrapper timed out at 120s, but the xcodebuild log completed successfully.
  - Log: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/logs/test_sim_2026-06-06T23-44-32-178Z_pid45897_e89d88f3.log`
  - Result bundle: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/result-bundles/test_sim_2026-06-06T23-44-32-179Z_pid45897_fc6bcf45.xcresult`
  - Confirmed passing tests:
    - `PaidWeightLoggerMVPPolicyTests.testSyncStatusCopyAvoidsRawPendingState()`
    - `PaidWeightLoggerMVPPolicyTests.testWeightSaveRequiresValidInput()`
    - `PaidWeightLoggerMVPPolicyTests.testWeightValidationMessageExplainsInvalidRange()`
    - `LogYourBodyUITests.testPaidMVPWeightEntrySavesWithKeyboardOpen()`

## Done When

A paid user can enter one weight value, save it without fighting the keyboard, and see a clear saved/sync state. Local simulator evidence proves that path for `182.4 lbs`.
