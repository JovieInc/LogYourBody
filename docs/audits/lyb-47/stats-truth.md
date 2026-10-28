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

## PR #1535 merge repair (2026-10-27)

Merged `origin/main` at `1a29635d5` without rebasing. The composed launch audit
retains main's bounded 900-second cold build and Stats truth's native UI selector.
Its fixed diagnostic digest is
`47d6ee6b7d56796527fa0154082f89a46c8a30be0ecfd5ce7e13866a600b633a`.
The trusted CLI regression admits these composed bytes and rejects both former
parent audits, all historical fixtures and every existing invalid-tooling case.

Extended the existing correction-ledger merge readiness guard with `--text`.
Real Git fixtures reproduce binary attributes hiding staged conflict markers
before the change, then verify refusal in initial resolution, staged resolution,
merge verification and staged retries. Clean retries pass. Used the same resolver
to retain both parents' classified correction receipts on this instance.

The harness owned pushes and PR updates. That repair extended
`packages/shared-lib/scripts/correction-coverage.mjs`.

Repair validation (Node 22.23.2, pinned pnpm 10.34.1 via Corepack):

- `corepack pnpm lint` and `corepack pnpm typecheck` passed (four Turbo tasks each).
- `corepack pnpm test` passed all eight Turbo tasks, including the real web
  production build, 186 shared-lib cases and 1,398 web Jest cases.
- `node --test --experimental-test-coverage
--test-coverage-include=scripts/correction-classifier.mjs
--test-coverage-lines=100 --test-coverage-branches=100
--test-coverage-functions=100 scripts/correction-classifier.test.mjs` passed
  all 11 cases with 100% line, branch and function coverage. Before the fix,
  `node --test --test-name-pattern='CLI resolves Git ledger conflicts'
scripts/correction-classifier.test.mjs` failed at `binary-marker: 0 !== 1`.
- `python3 -m pytest -p no:cacheprovider scripts/tests/test_runner_routing.py -q`
  passed all 44 cases. Bashcov is unavailable here; the separate routing shell
  coverage check needs its CI receipt.
- `python3 scripts/ios/test_launch_ui_regression_audit.py` passed 12 cases;
  `python3 scripts/ios/launch-ui-regression-audit.py --artifact-dir
/tmp/pr1535-launch-ui` and `bash -n scripts/ios/launch-quality-audit.sh` passed.
- `node packages/shared-lib/scripts/correction-coverage.mjs --base-ref origin/main`,
  the matching `correction-ratchet.mjs` and `guard-reference.mjs` commands passed:
  64 mechanized rules, no missing guards and the unchanged 11 public-copy findings.
- From `apps/ios`, `XDG_CACHE_HOME=/tmp/pr1535-swiftlint-cache swiftlint lint
--strict --config .swiftlint.yml --cache-path /tmp/pr1535-swiftlint-cache/lint`
  passed with zero violations in 486 files. SourceKit-only rules remain unavailable
  on Linux. `xcodebuild` is absent; native execution remains required in CI.

The standalone routing coverage reader cannot run without Bashcov's result file.
Initial sandboxed Git-fixture checks needed an unsandboxed retry; the successful
checks above retain all thresholds. The system pnpm is 9.15.4, so root validation
used Corepack's pinned version; SwiftLint ran directly with its writable cache.
GBrain write `put lyb-47-stats-truth-merge-repair` and readback
`get_page lyb-47-stats-truth-merge-repair` both failed with curl error 7 at
localhost:7801. The unsandboxed query also timed out after 30 seconds; neither
write persistence nor readback was established. This document retains the findings.

## PR #1535 launch-quality repair (2026-10-28)

Merged `origin/main` at `e3fffe422` without rebasing in `030145c7e` before
repairing the failed check. Main's correction-readiness implementation and expanded
marker fixtures supersede the branch's earlier versions; all 129 correction
receipts survived the repository resolver. The composed launch audit retains
main's early shell-fixture preflight, the existing cold-build limit and every
native selector, including Stats truth. Its digest is
`ad4098afa11c60dededb52592a74de1c3374d84f87da891f754b4b47f6aba2aa`.
Routing tests admit only the composed audit and reject both merge parents and all
retained historical/invalid-tooling fixtures. The diagnostic workflow conflict
resolution updates only that audit pin relative to main.

`gh run view 40434998769 --repo JovieInc/LogYourBody --log-failed` identified
one native failure: `testStatsTruthFFMIUsesCanonicalJOV3331ValueAndExportsDerivedEvidence`
reported `privacy` and `source` mismatches. The fixture enabled observation date,
range and provenance while its expectation hid them. The PNG oracle also assumed
range visibility followed date visibility. Extend the existing `SharePNGTruth`
template with required independent range and source fields; update every existing
expectation and the failing fixture. An eight-combination calibration covers all
date/range/source states, rejects missing/leaked fields, and requires derived
evidence in every state. Product output and privacy controls retain their behavior.

Validation on Node 22.23.2 and Corepack's pinned pnpm 10.34.1:

- `bash scripts/codex-setup.sh` passed with the frozen lockfile.
- `corepack pnpm lint`, `corepack pnpm typecheck`, and `corepack pnpm test`
  passed: four, four and eight Turbo tasks respectively, including the web
  production build, 192 shared-lib cases and 1,411 web Jest cases.
- `python3 -m pytest -p no:cacheprovider scripts/tests/test_runner_routing.py -q`
  passed all 52 cases. Its first sandboxed attempt passed 50 cases but could not
  bind the two Unix-socket fixtures; the complete unsandboxed run passed.
- `node --test --experimental-test-coverage
--test-coverage-include=scripts/correction-classifier.mjs
--test-coverage-lines=100 --test-coverage-branches=100
--test-coverage-functions=100 scripts/correction-classifier.test.mjs` passed
  all 11 cases with 100% line, branch and function coverage outside the sandbox.
- `python3 scripts/ios/test_launch_ui_regression_audit.py` passed all 12 cases;
  `python3 scripts/ios/launch-ui-regression-audit.py --artifact-dir
/tmp/pr1535-ui-audit`, `bash -n scripts/ios/launch-quality-audit.sh`, and
  `git diff --check` passed.
- From `apps/ios`, `XDG_CACHE_HOME=/tmp/pr1535-swiftlint-cache swiftlint lint
--strict --config .swiftlint.yml --cache-path /tmp/pr1535-swiftlint-cache/lint`
  passed with zero violations in 493 files. SourceKit-dependent rules are
  unavailable on Linux. The initial root SwiftLint attempt changed Corepack's
  cache via `XDG_CACHE_HOME` and could not download pnpm in the sandbox; the direct
  SwiftLint invocation above used the existing binary and a writable cache.
- `bash scripts/codex-setup.sh --run product:check` passed. The earlier
  `corepack pnpm product:check` attempt delegated to the system pnpm 9.15.4;
  the bootstrap wrapper supplied the pinned pnpm for the successful run.
- Correction coverage, ratchet and guard-reference commands with
  `--base-ref origin/main` passed: 90 guarded rules and the same 11 retained
  public-copy baseline findings. Their Git child processes required an
  unsandboxed run. No baseline or threshold was lowered.

The original failed native run proves the old expectation failure. This host
has neither a Swift compiler nor Xcode; `xcodebuild ... build-for-testing` exits 127. The new calibration, fixed PNG/OCR test, complete native suite, UI execution
and exact-head coverage remain unverified until the harness-pushed CI run.
Bashcov shell coverage also remains a CI receipt. Local source and JS checks
cannot substitute for either native execution or shell coverage.

GBrain `put lyb-47-png-truth-repair-20261028` and
`get lyb-47-png-truth-repair-20261028` both failed with curl error 7 at
localhost:7801. Neither persistence nor readback could be established. This
document retains the findings for the harness.

## 2026-10-28 chart accessibility repair

`git fetch origin main` refreshed the base; `git merge --no-edit origin/main`
reported already up to date at main `e3fffe422`. Read the current failure with
`gh run view 40633922695 --repo JovieInc/LogYourBody --log-failed`. The unit target
executed 1,959 cases with 50 skipped and no failures, including the preceding PNG
repair. The UI target had one failure among 29 cases: the Stats truth drilldown
could not find `metric_detail_chart_plot`.

Its native hierarchy contained the rendered “Weight chart” with the parent
identifier `metric_detail_chart`. Give `chartCard` explicit accessibility
containment before its identifier, matching the neighboring headline and related
containers. This preserves the adjustable plot's own identity and value. Retain
the existing native drag, selection persistence and observation-context assertions.

Extend the existing launch UI regression audit to reject missing containment,
ignored/combined children and containment placed after the identifier. Include
the audit, its mutation suite and chart source in shared-lib's existing Turbo
test inputs so those changes invalidate cached results. Record the correction in
the existing ledger. No new workflow, baseline, timeout or gate is needed.

Verification on Node 22.23.2 with pinned pnpm 10.34.1:

- `python3 scripts/ios/launch-ui-regression-audit.py --artifact-dir
/tmp/pr1535-before-audit` failed on the unchanged chart with the new containment
  violation. The same command with `/tmp/pr1535-after-audit` passed after the fix.
- `python3 scripts/ios/test_launch_ui_regression_audit.py` passed all 15 cases.
- `corepack pnpm lint`, `corepack pnpm typecheck`, and `corepack pnpm test`
  passed: four, four and eight Turbo tasks respectively. The test run reused six
  cached tasks; shared-lib executed all 192 Vitest and 122 Node cases. Its audit
  wrapper measured 99% audit line coverage. The initial sandboxed test attempt
  failed on denied subprocess operations; the complete run with access passed.
- `swiftlint lint --strict --no-cache --config apps/ios/.swiftlint.yml
apps/ios/LogYourBody/Components/FullMetricChartView+Part01.swift` passed with
  zero violations. SourceKit-dependent rules are unavailable on Linux. The first
  cached attempt could not write `/var/tmp/SwiftLint`; `--no-cache` resolved it.
- Correction coverage against both `origin/main` and pre-repair
  `8faae69298655000864c00f1d8b3ce09d40df3c2` passed: 91/91 mechanized rules.
  `correction-ratchet.mjs --base-ref origin/main` and
  `guard-reference.mjs --base-ref origin/main` passed, retaining the same 11
  public-copy findings. These Git-backed guards required subprocess access.
- `xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination
'platform=iOS Simulator,name=iPhone 16' build-for-testing` from `apps/ios`
  exited 127 because Xcode is unavailable. Native execution and exact-head
  coverage remain required from the harness-pushed CI run.

GBrain write and same-slug readback succeeded for
`lyb-47-chart-identity-repair-20261028` with network access outside the sandbox.
The initial sandboxed query, write and readback attempts could not connect.

The harness owns pushes and PR edits. Use exactly this machine line in the PR body:

Machine: built scripts/ios/launch-ui-regression-audit.py
