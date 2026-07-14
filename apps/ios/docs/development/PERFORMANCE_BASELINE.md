# iOS Performance Baseline & Instrumentation

This document describes the DEBUG-only performance instrumentation added in the
"rock solid & blazing fast" campaign (Phase 0) and how to capture the baseline
numbers that later phases must not regress.

All instrumentation is compiled out of release builds — it lives behind `#if DEBUG`
and, for the frame monitor, an explicit launch flag. There is **zero shipping overhead**.

## What's instrumented

### `PerfSignpost` (`LogYourBody/Utils/PerfSignpost.swift`)
Thin wrapper over `OSSignposter` (category `perf`). Use it to time hot paths so they
show up as intervals in Instruments' **os_signpost** / **Points of Interest** track.

| Signpost name                  | Where                                                            | Measures |
|--------------------------------|-----------------------------------------------------------------|----------|
| `launch_first_dashboard_frame` | `LaunchMetrics.markFirstDashboardFrame()`                       | Launch → first dashboard frame (point event) |
| `scrub_select_closest`         | `selectClosestMetric(to:)`                                      | Timeline header cursor → metric selection |
| `scrub_update_animated_values` | `updateAnimatedValues(for:)`                                    | Per-index hero value recompute (3× interpolation) |
| `dashboard_derived_refresh`    | `scheduleDashboardDerivedStateRefresh(...)`                    | Derived-state rebuild on data/index change |
| `chart_generate` / `_async`    | `MetricChartDataHelper.generateChartData[Async]`               | Sparkline/chart compute (cache miss cost) |

API: `PerfSignpost.measure("name") { ... }`, `begin/end`, `event("name", "msg")`.

### `LaunchMetrics` (`LogYourBody/Utils/PerfSignpost.swift`)
- `LaunchMetrics.begin()` — called in `LogYourBodyApp.init()` (earliest hook).
- `LaunchMetrics.markFirstDashboardFrame()` — called in `DashboardViewLiquid.onAppear`;
  logs `launch→firstDashboardFrame <ms>` once via `AppLogger.ui`.

### `FrameHitchMonitor` (`LogYourBody/Utils/FrameHitchMonitor.swift`)
CADisplayLink-based hitch counter. A frame is a **hitch** if its render interval
exceeds 1.5× the display's nominal frame budget. Only runs when explicitly enabled:

- Launch argument: `-lybPerfHitchMonitor`, or
- Environment variable: `LYB_PERF_HITCH_MONITOR=1`

Call `FrameHitchMonitor.shared.flush(label:)` after a measured gesture to log
`hitches[label] <hitches>/<frames> frames, worst <ms> ms` and reset counters.

## How to capture the baseline

### Launch → first frame
1. Run the app (Debug) on a physical device (preferred) or simulator.
2. Filter the Console / unified log for subsystem `co.logyourbody.*`, category `ui`.
3. Read the `launch→firstDashboardFrame <ms>` line. Take the median of 3 cold launches.

Or in Instruments: profile with the **os_signpost** instrument and read the
`launch_first_dashboard_frame` point event.

### Scrub / scroll hitches
1. Launch with the hitch monitor enabled, e.g. in the scheme's Run arguments add
   `-lybPerfHitchMonitor`, or run a UI test with that argument
   (the `-lybUITestPhotoTimelineHUDFixture` fixture seeds timeline data).
2. Perform a consistent gesture (e.g. drag the timeline scrubber end-to-end 3×).
3. Read the `hitches[...]` log line, or use Instruments **Animation Hitches** /
   **Time Profiler** alongside the `scrub_*` signpost intervals.

### Recommended: Instruments
Profile the **os_signpost**, **Time Profiler**, and **Animation Hitches** instruments
on a physical device. The `scrub_*` and `chart_generate` intervals pinpoint the
main-thread work to attack in Phase 2.

## Baseline numbers (fill in from a real device run)

> Capture on a fixed device (e.g. iPhone 15, iOS 26) with the
> `-lybUITestPhotoTimelineHUDFixture` data set, and record here + in the PR.

| Metric                              | Baseline | Target |
|-------------------------------------|----------|--------|
| Launch → first dashboard frame (ms) | _TBD_    | hold / ↓ |
| Scrub hitches (end-to-end drag)     | _TBD_    | ~0 |
| Cold scroll hitches (home)          | _TBD_    | ~0 |
| Worst frame during scrub (ms)       | _TBD_    | < frame budget |

These become the regression gate for Phases 2–4.
