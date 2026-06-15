# JOV-3184 Performance Budget Summary - 2026-06-15

## Summary

The iOS performance audit now emits a repeatable budget artifact instead of only raw `xcodebuild` logs. `scripts/ios/performance-audit.sh` writes both `summary.md` and `summary.json` using `scripts/ios/performance-budget-summary.py`.

## Budgets

| Check                      |             Default budget | Source                                                            |
| -------------------------- | -------------------------: | ----------------------------------------------------------------- |
| Performance unit total     |                       2.0s | `xcresulttool get test-results tests` or xcodebuild log fallback  |
| Slowest performance unit   |                      0.75s | `xcresulttool get test-results tests` or xcodebuild log fallback  |
| Launch performance UI test | 90.0s hard / 60.0s warning | `LogYourBodyUITests/testLaunchPerformance` result-bundle duration |

The helper also records whether XCTest published granular launch metric statistics. On the current Xcode lane, `xcresulttool get test-results metrics` returns an empty payload for `XCTApplicationLaunchMetric`, so the gate reports a warning and keeps the issue open for a focused Instruments or ETTrace capture before frame/hitch budgets are tightened.

## Validation

- `python3 scripts/ios/performance-budget-summary.py ...` against the `20260614-final` launch-enabled artifacts produced a passing summary with 0.030s total performance-unit runtime and 58.824s launch UI-test duration.
- `python3 scripts/ios/performance-budget-summary.py ... --launch-skipped` produced the CI-mode summary with launch performance marked skipped.
- `bash -n scripts/ios/performance-audit.sh`
- `python3 -m py_compile scripts/ios/performance-budget-summary.py`
