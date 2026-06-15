# JOV-3217 Performance Trace Budget - 2026-06-15

## Summary

This pass added a deterministic timeline performance workflow and wired it into the existing iOS performance-budget summary path. The workflow launches the seeded photo timeline, switches Avatar and Photo modes, opens Stats, then returns to Timeline.

Simulator `xctrace` app recording is not reliable on the current local Xcode 17F42 lane: simulator device, attach-by-name, and app-launch recordings did not honor `--time-limit`; force-stopped traces exported with `Document Missing Template Error`. Host `xctrace` against `/bin/sleep` completed, so the blocker is specific to simulator app/device recording here rather than `xctrace` availability.

## Enforced Budgets

| Budget                            | Threshold | Source                                      |
| --------------------------------- | --------: | ------------------------------------------- |
| Timeline trace workflow warning   |     28.0s | `PERF_WARN_TIMELINE_TRACE_WORKFLOW_SECONDS` |
| Timeline trace workflow hard fail |     35.0s | `PERF_MAX_TIMELINE_TRACE_WORKFLOW_SECONDS`  |

The workflow can be run locally through:

```bash
RUN_TIMELINE_TRACE_WORKFLOW=true \
RUN_SWIFTLINT=false \
RUN_PERFORMANCE_UNIT_TESTS=false \
RUN_LAUNCH_PERFORMANCE=false \
DESTINATION='platform=iOS Simulator,name=LYB Golden iPhone 16' \
bash scripts/ios/performance-audit.sh
```

## Observed Run

| Check                                                                     | Result  |
| ------------------------------------------------------------------------- | ------- |
| Focused UI workflow                                                       | Passed  |
| XcodeBuildMCP duration                                                    | 23.457s |
| Direct `xcodebuild test-without-building` duration during attempted trace | 22.564s |
| Summary status                                                            | Passed  |

Summary smoke command:

```bash
python3 scripts/ios/performance-budget-summary.py \
  --artifact-dir /tmp/lyb-jov-3217-summary-smoke \
  --destination 'platform=iOS Simulator,name=LYB Golden iPhone 16' \
  --unit-skipped \
  --launch-skipped \
  --timeline-workflow-xcresult /Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-f25e48b4f67a/result-bundles/test_sim_2026-06-15T10-39-44-756Z_pid40762_2f6a4f41.xcresult \
  --timeline-workflow-log /Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-f25e48b4f67a/logs/test_sim_2026-06-15T10-39-44-756Z_pid40762_c006f2ea.log
```

## Instruments Attempts

Available templates include `Time Profiler`, `SwiftUI`, `Animation Hitches`, and `App Launch`.

Failed simulator capture command:

```bash
xcrun xctrace record \
  --template 'Time Profiler' \
  --device 7EB60D3E-3637-43EA-969D-167ADC72BAEC \
  --all-processes \
  --time-limit 35s \
  --output /tmp/lyb-jov-3217-trace-20260615-034120/time-profiler.trace \
  --no-prompt \
  --quiet
```

The UI workflow passed while recording, but `xctrace` continued past the 35s limit. After SIGTERM, export failed:

```text
Export failed: Document Missing Template Error
```

Additional simulator `--attach LogYourBody` and `--launch -- LogYourBody.app` Time Profiler attempts also hung past their requested limits. Attaching by host PID returned `Cannot find process for provided pid`.

Host smoke proof that `xctrace` itself works:

```bash
xcrun xctrace record \
  --template 'Time Profiler' \
  --time-limit 3s \
  --output /tmp/lyb-jov-3217-host-xctrace-smoke-20260615-034817/host-sleep.trace \
  --no-prompt \
  --quiet \
  --launch -- /bin/sleep 1
```

## Trace Budgets To Enforce Once Device Capture Works

| Area                                        |    Budget |
| ------------------------------------------- | --------: |
| Cold launch to usable timeline hero         |   <= 2.5s |
| Warm launch to usable timeline hero         |   <= 1.2s |
| Timeline scrub p95 frame time               | <= 16.7ms |
| Timeline scrub p99 frame time               | <= 33.3ms |
| Hitches over 250ms during five-second scrub |         0 |
| Avatar/Photo switch hitches over 250ms      |         0 |

The current PR does not claim those frame or hitch budgets passed. It creates the deterministic workflow and summary hooks needed to enforce them when a valid device/simulator trace can be captured.
