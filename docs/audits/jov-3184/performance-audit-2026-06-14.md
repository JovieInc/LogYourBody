# JOV-3184 iOS Performance Audit - 2026-06-14

## Summary

This pass targeted the dashboard timeline and progress-photo path because those were the highest-risk code-backed sources for janky swiping, slow timeline scrubbing, and heavy first render. The fixes landed here remove obvious main-thread image work and repeated timeline sorting/filtering. The run did not produce granular launch-time statistics from `xcresult`, so frame and hitch budgets still need an Instruments or ETTrace capture before this issue can be called fully done.

## Findings

1. Progress photo loading did decode and encode-adjacent work on the main actor.
   - Symptom: timeline thumbnails and photo stages can hitch while images load.
   - Evidence: `OptimizedProgressPhotoView` decoded `UIImage(data:)`, read local files, created per-load URL sessions, and used `pngData()` for cache cost inside the view-owned load path.
   - Fix: moved URL/file loading, decode, orientation normalization, and downsample into `ProgressPhotoImagePipeline`; replaced `pngData()` cost calculation with pixel-byte estimation; reused one cached URL session.
   - Validation: `ProgressPhotoImagePipelineTests` covers downsampling and cache-cost policy.

2. Timeline scrub data was recomputed from raw metrics during interaction.
   - Symptom: dragging the timeline can repeatedly sort/filter metric arrays and local-date scan collections.
   - Evidence: `TimelineDataProvider` filtered photos/data and sorted metrics in lookup/generation methods.
   - Fix: `loadMetrics` now builds sorted metrics, photo/data subsets, local-date lookup, and snap-point dates once per input change; nearest data-date lookup uses binary search.
   - Validation: `DashboardTimelineProviderPerformanceTests` covers sorted indexes, nearest-date lookup, and duplicate same-day metrics.

3. There was no repeatable local performance audit entrypoint.
   - Symptom: launch-quality/performance checks were easy to skip or run differently across agents.
   - Fix: added `pnpm ios:performance-audit`, which runs strict SwiftLint, the targeted performance unit tests, and `LogYourBodyUITests/testLaunchPerformance`, writing logs under ignored `apps/ios/test_results/performance-audit/`.
   - Validation: `pnpm ios:performance-audit` passed on `LYB Golden iPhone 16`.

## Metrics

| Check                     | Result   | Notes                                                                          |
| ------------------------- | -------- | ------------------------------------------------------------------------------ |
| SwiftLint strict          | Passed   | `pnpm ios:performance-audit`                                                   |
| Timeline/image unit tests | 4 passed | `DashboardTimelineProviderPerformanceTests`, `ProgressPhotoImagePipelineTests` |
| Launch performance smoke  | Passed   | UI test duration 26.523s; `xcresult` statistics were empty                     |

## Next Step

Capture one focused dashboard timeline trace on a release-like build: open app to the post-MVP timeline, switch Avatar/Photo once, scrub the timeline for five seconds, and export Time Profiler plus SwiftUI/Animation Hitches evidence. Use that trace to set concrete budgets for launch time, scroll frame pacing, and hitches over 250ms.
