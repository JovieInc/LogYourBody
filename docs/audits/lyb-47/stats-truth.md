# LYB-47 Stats truth contract

The rollout is `metric_stats_truth_v1`, read through the existing analytics port.
Unknown/off keeps the existing surface. Direction stays neutral even with a saved
numeric target: the app has no validated eligibility contract for safe goal
progress. No clinical or aesthetic progress is inferred from direction.

## Provider audit

The original Stats weight sparkline used the last seven observations, not seven
days. Body-fat and FFMI sparklines intentionally included estimates from
`MetricsInterpolationService`; this was not evidence of fabricated measurements.
Steps previously filled missing daily totals with zero in the small chart.
The new path uses the existing full-chart providers, retaining their timestamps
and presence labels, and omits missing/invalid Steps without dropping recorded
zero. It creates no daily resampling or replacement measurements.

FFMI still comes from the existing normalized calculation and interpolation
service (JOV-3331). Its provenance explicitly says that it uses smoothed weight,
body fat and height. No second FFMI calculator or formula was added.

## Shared rules

- Display period: a rolling 7/30/90/180/365 calendar-day window ending at the
  captured reference time, inclusive at both ends, or all recorded history up to
  that time. Calendar arithmetic respects local DST; future samples are excluded.
  Month/year tabs retain their existing approximate day counts, now spelled out.
- Comparison period: first and last eligible observation timestamps inside that
  display window, printed with year, time and time-zone abbreviation. These may
  span fewer days than the display window. Delta is last minus first.
- Mean: arithmetic mean of every eligible observation, not a time-weighted mean,
  daily mean, or mean of a thinned chart. Both mean and delta require at least two
  different timestamps. Multiple readings at one timestamp cannot prove change.
- Eligibility: finite nonnegative present/estimated observations. Missing,
  interpolated and carried (`lastKnown`) samples cannot establish a comparison.
  Estimates keep their evidence label. No missing sample becomes zero.
- Rounding: providers retain their existing precision (including canonical FFMI).
  Convert weight to the display unit before comparison; round the delta once to
  one decimal, halfway away from zero. A rounded zero reads “Unchanged at
  displayed precision”. Body-fat differences use percentage points. Headlines
  use one decimal (whole counts for Steps); the arithmetic mean uses the existing
  average formatter. Rounded endpoints are never subtracted.
- The selected observation is the latest eligible point at or before the selected
  measurement date, or the latest observation for Steps. Its date/age is distinct
  from both periods. An old observation remains visible and is marked outside the
  display period when applicable; insufficient data never reads “No change”.
- Cloud sync state/time and available Apple Health access status are separate
  text. Neither `updatedAt` nor a successful sync makes an observation current.
  Missing HealthKit samples do not establish read denial. The existing access
  status is displayed without deriving permissions from sample absence.
- Source lookup matches the selected timestamp and value. Conflicting/absent
  source matches read “Source unavailable or mixed”; a historical selection never
  borrows the latest sample's source. Field-level weight/body-fat attribution is
  used in history. Detail shares freeze only their selected metric.

Stats cards, native detail, Progress/timeline comparison copy and contextual
shares consume `MetricObservationSummary` and the existing range-stat calculator.
Detail retains the selected point after drag release, validates it against the
current series fingerprint, and preserves the timeline date on navigation.
The observation plot uses elapsed timestamps and dots (daily Steps bars), with
no continuous line or area across gaps. The existing Progress chart keeps its
linear, calendar-gap-aware geometry; its gated view shows raw observations rather
than an unlabeled smoothing series. Share metadata can wrap without a fixed line
cap; evidence remains mandatory and other details follow existing share options.

## Verification and remaining native evidence

Existing XCTest suites now cover unequal dates, no/single/old observations,
missing/invalid Steps versus recorded zero, mixed sources, timezone/DST, unit
conversion, rounding, canonical FFMI, goal/no-goal neutrality, and cross-surface
snapshots. The existing launch-quality runner includes
`testStatsTruthDrilldownKeepsHeadlineAndFocusWithObservationProvenance` and requires
its native receipt. Existing share PNG/OCR truth tests cover derived FFMI output.

The launch UI audit's mutation fixtures reject index-domain plotting, continuous
observation lines, single-timestamp comparisons, and positive/negative direction
styling. Its existing shared-lib wrapper propagates Python test failures.

This Linux worktree cannot execute Xcode, simulator UI, native XCTest, PNG/OCR or
native coverage. Those receipts remain required from the real native runner at
the harness-pushed head before release/rollout; local SwiftLint and JS/static
checks do not replace them. The screenshot itself was not available locally;
its reported interpretation ambiguity was not treated as proof of incorrect
readings. GBrain was unavailable at localhost:7801.

Local validation on 2026-10-25:

- Root `pnpm lint` and `pnpm typecheck` passed.
- `VITEST_MAX_WORKERS=1 pnpm test --force --env-mode=loose --concurrency=1`
  passed all eight Turbo tasks, including a real web production build and all
  156 shared-lib tests. Earlier concurrent attempts hit sandbox EPERM and a
  five-second fixture timeout; the unchanged suite passed serially outside the
  sandbox. No timeout or quality gate was relaxed.
- `pnpm lint:swift` passed with a writable `/tmp` cache: zero violations in 464
  files. This host skips five SourceKit-dependent rules, so this is not Swift
  compilation proof.
- `python3 scripts/ios/test_launch_ui_regression_audit.py`: 12 tests passed,
  including rejecting the actual mutated source regressions.
- Existing correction behavior suites: 42 tests passed; correction coverage and
  the immutable-base ratchet passed. The existing 11 public-copy baseline
  warnings remain unchanged.
- `pnpm product:generate`, product checks, repository source parity,
  `bash -n scripts/ios/launch-quality-audit.sh`, and `git diff --check` passed.
  The new correction source URL is registered; generated endpoint output was
  regenerated. Unrelated marketing-asset timestamp churn was restored.
- Both requested `xcodebuild` build-for-testing and test commands returned 127
  (`xcodebuild: command not found`). Native tests, UI screenshots, OCR and
  coverage are added/wired but have no execution receipt from this host.
- GBrain `put lyb-47-stats-truth` and `get_page lyb-47-stats-truth` both failed
  with curl error 7 at localhost:7801. Neither write persistence nor readback
  could be verified. This repository document retains the findings for handoff.

Progress explicitly labels its calendar-day observation domain. Selection maps
that plotted day/value/occurrence back to the original timestamp before looking
up provenance or freezing a share. A native DST regression covers that mapping.
No new Swift files or target memberships were needed. The harness owns pushing,
PR creation and merge; this run only creates local commits.

The existing share Date switch also removes comparison endpoint dates. Its
undated trend still states first-to-last observation and the observation mean;
it does not leave hidden dates in the Trend field. A native PNG truth regression
covers Date off with Trend on.
