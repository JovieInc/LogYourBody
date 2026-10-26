# LYB-44 chart interaction receipt

## Ownership and inspected source

Canonical intake: [LYB-44](https://linear.app/jovie/issue/LYB-44), read on
2026-10-25. Linear reports Tim White as assignee, status Todo, no blocking
relations. This Symphony-dispatched lane implements the change; the harness
owns push, PR creation, CI and merge. This document is not a production receipt.
The original conversation-audit file is unavailable on this host; its request
is retained in the canonical issue.

Benchmark base: `3a6516fb61f6bdc2af76b5a980553640a33679e9` (`origin/main`
at dispatch). The unpushed change was subsequently rebased onto
`8a85ccc43c12033888f478753444780674e89464`, preserving its newly merged
LYB-194 privacy correction and guard. The chart source is unchanged by that
base update. Inspected
`HomeV2TrendChart`, `HomeV2ChartIntegrity`, their Home/Progress callers, and
`FullMetricChartView`'s separate detail-chart selection path. LYB-170 is Done
and established the active shared Home/Progress chart's scale, gap and label
semantics. This change stays in that shared chart; detail-chart behavior is
outside this bounded fix.

The source bottleneck is repeated `plotted` evaluation during selection:
filtering, date normalization, sorting, run construction and selection-map
grouping. Marks are sorted by value within a day, so choosing the first daily
mark selected the lowest value rather than the latest reading. The regression
fixture has morning 170, evening 190, average 180; the old source chooses 170
in both input orders.

## Budgets and measurement contract

These are acceptance targets, not claims of device execution. Use a Release
build on an iPhone 16, record the actual iOS version/build and gate state, and
compare the base and candidate on the same device. Use locally loaded data,
30 warm screen/range transitions and at least 250 scrub events per metric.
Exercise Steps, Weight (daily plus average), Body fat and FFMI, 1M/1Y/All,
including sparse gaps and duplicate days. Separately stress ten years of
daily data. Do not include network loading or cold app launch in chart latency.

| Interaction            | Clock boundary                                                          | Acceptance budget                               |
| ---------------------- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| Initial chart          | Locally loaded series supplied to first complete, stable plot           | p95 <= 100 ms                                   |
| Range zoom / pager pan | Range tap or completed page gesture to stable chart                     | p95 <= 100 ms                                   |
| Continuous pan / scrub | Input event to matching playhead displayed                              | p95 <= 16.7 ms; p99 <= 33.3 ms                  |
| Tooltip                | Input event to matching date, value and series label displayed together | p95 <= 16.7 ms; p99 <= 33.3 ms                  |
| Interaction frames     | Instruments Animation Hitches during gestures                           | <= 1% frames over 33.3 ms; no frame over 100 ms |

The current chart has range tabs and native X selection, with no free chart
pan or pinch zoom. Measure existing range changes and the containing pager;
this fix adds no gesture or layout. Capture input timestamps and displayed
frames in Instruments/recording rather than using XCTest polling intervals
as latency measurements. Repeat with VoiceOver adjustments, Reduce Motion
and accessibility text sizes; labels must remain readable and identify the
same sample as the highlighted point.

The policy XCTest has separate p95 budgets: cold preparation <= 100 ms,
cached preparation plus nearest-day lookup <= 2 ms, formatting <= 4 ms.
It takes 25 cold samples and 250 warm/format samples. Debug uses 365 days;
Release uses 3,650 days. These selectors, configurations and fixture sizes
must remain distinct in receipts. Timing under concurrent build/test load
is noisy and does not establish device frame performance.

## Local before/after evidence

2026-10-25, Linux x86_64, Swift 6.2.1, Foundation/XCTest, sequential runs.
The temporary harness compiled the actual `HomeV2ChartIntegrity`, point,
presence, range, trend-policy and observed-point source declarations. It
excluded the unrelated UIKit-backed tick formatter and SwiftUI rendering.
It compiled the six retained LYB-44 XCTest methods without changing them.
Baseline source came from the base Git revision. These are policy execution
receipts, not execution of the iOS app or its native Unit test plan.

| p95, milliseconds           | Base (`-O`, 3,650 days) | Candidate (`-O`, 3,650 days) | Candidate (`-Onone -DDEBUG`, 365 days) |
| --------------------------- | ----------------------: | ---------------------------: | -------------------------------------: |
| Cold preparation            |                  57.787 |                       53.427 |                                 14.180 |
| One scrub policy evaluation |                  45.606 |                        0.003 |                                  0.008 |
| Tooltip formatting          |                   0.551 |                        0.433 |                                  0.563 |

Base cold timing includes one plot build and selection-map construction;
candidate cold timing also prepares the minimum-days decision. Base scrub
timing includes one original `selectedSample` evaluation (the view reads it
several times); candidate scrub includes cache validation and binary lookup.
Neither column includes Swift Charts layout, rasterization or input delivery.

Regression proof: the retained latest-reading test executes against the base
and fails twice (`170 != 190`, both input orders). All six candidate policy
tests pass in optimized and Debug runs. Coverage includes daily/average
provenance, missing/nonfinite/carried data, duplicate timestamps and IDs,
gaps, earlier-date midpoint ties, empty histories, cache reuse across 1,000
scrubs, every render-input invalidation, equal reloaded arrays, retained NaN
inputs, and gate-off rollback semantics.

Temporary artifacts: `/tmp/lyb-44-receipt/` contains `extract.py`, extracted
`baseline.swift` / `head.swift`, binaries, baseline failure and timing logs,
and candidate test logs. Compile commands used `swiftc -O` and
`swiftc -Onone -DDEBUG`, each with `-module-cache-path` under that directory.

Repository checks (using the pinned pnpm 10.34.1 through
`bash scripts/codex-setup.sh --run`):

- `pnpm lint`, `pnpm typecheck`: pass.
- `pnpm product:check`: pass after registering the issue URL and running
  `pnpm product:generate`; generated files, URL drift and registry assertions pass.
- `pnpm test`: pass through Turbo; shared-lib executes fresh on the final
  chart source and rebased ledger: 157 Vitest cases and 106 Node cases pass.
- `pnpm test --filter=@logyourbody/shared-lib`: fresh pass, including the
  existing per-point plot guard and the new runtime-wiring regression.
  The initial sandbox run failed on subprocess/socket `EPERM`; rerunning
  with those test permissions passed without code or gate changes.
  After rebase, the existing correction-coverage case exceeded its unchanged
  five-second timeout during concurrent checks; the standalone shared suite
  passed with the original timeout and assertions.
- Scoped `swiftlint lint --strict --no-cache` on the three changed Swift
  files: zero violations. This Linux binary skips SourceKit-dependent
  rules; the native strict lint check remains required.
- `swiftc -frontend -parse` on all three changed Swift files: pass.
- Correction ratchet against the pinned PR base: pass, retaining the unrelated
  existing 11-finding web-copy warning baseline and empty privacy baseline.
- `python3 scripts/repository_docs.py`: source parity passes.

## Native and release handoff — not yet verified

`xcodebuild` is absent here (the attempted scoped Unit invocation exits 127).
No native build, iOS coverage, device trace, production, TestFlight or merge
receipt has been produced. Required CI and native evidence must gate shipping.
Run the repository's real Unit selector on the PR head, including:

```sh
cd apps/ios
xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody \
  -testPlan Unit -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LogYourBodyTests/HomeV2MetricEditorialTests \
  -resultBundlePath /tmp/lyb-44-unit.xcresult test
```

Retain the native runner's exact commit, selector, XCTest cases and coverage
receipts. Use a Release device build for the display-latency matrix above;
record build number, commit, device, OS, dataset, locale/time zone, gate state,
p95/p99, frame counts and the trace/recording location. Recheck tooltip
values against the seeded source, including same-day readings, equal
daily/average values, a missing daily reading and a range/data change while
selected. Check the production/TestFlight build containing the merged commit
with the gate enabled only for the intended internal principal before rollout.

`chart_playhead_v2` is read through the existing analytics platform port.
It is default-off when absent; no Statsig configuration was changed. Gate on
uses the view-owned cache, latest daily reading per day (latest average only
when daily is absent), binary nearest lookup and same-day event coalescing.
An exact timestamp tie retains the lower value, independent of input order.
All original marks, linear runs/gaps, domains, units, formatting and VoiceOver
adjustment ordering remain. Changes to selectable data clear active selection.
Gate off retains the previous same-day selection policy and uncached path.

Keep the gate off if any budget or tooltip assertion fails. Disable it to
restore the selection behavior immediately; revert this bounded PR if either
gate state regresses or values become incorrect. No subjective visual decision
was required. No workflow, gate requirement or legacy screen was changed or removed.
The registry registers the canonical issue evidence URL; `pnpm product:generate`
updates its generated web endpoint allowlist. Generated outputs were not edited
by hand. The commit hook's URL drift check remains enforced.

GBrain search failed because the local service at `127.0.0.1:7801` is down;
the connected read-only fallback requires reauthentication. Both the write
(`gbrain put lyb-44-chart-playhead`) and same-slug readback were attempted and
failed to connect. No durable memory persistence was verified.
