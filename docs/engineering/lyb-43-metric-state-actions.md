# LYB-43 metric state action handoff

Based on main d587a9371 after retaining the incoming correction records.

The candidate moves the native Button into MetricSummaryCard. Callers pass
`detailAction` instead of wrapping the card. With `metric_card_actions_v1`
enabled, empty/error state actions take precedence over navigation. Loading
has no action, button trait or actionable hint. Unavailable cards without a handler
remain static. Control labels name the supplied action even when hints are disabled; hints
describe that action, including permission actions.

The new gate uses the existing platform feature-flag port and is intended to
remain off until native acceptance. No remote rollout configuration was changed.
The new action gate also requires the existing `metric_card_identity_v1`
gate. Both must be enabled for the repaired state/action contract; neither gate
is bypassed. The existing chart/source summary and legacy rollback remain. Trend-period speech from #1413 and JOV-6090's full-width trend
layout are preserved. Linear reports JOV-6090 / LYB-42 as Done; this branch starts
from main containing both changes and the bounded identity follow-up #1443.

All production metric callers use the new action API, preserving their handlers
and button styles. No numeric data, calculations, charts or data-plane behavior
change. The DEBUG preview doubles as a deterministic, mounted app fixture using the
production DashboardMetricsList (including lazy layout and drag wrappers) under
`-lybUITestMetricCardFixture`. Add/retry handlers count invocations and change the
card to data; the permission handler navigates to a fixture destination. This
checks callback delivery, not HealthKit authorization or a saved measurement.

The source regression retains an old external-button fixture. A native legacy
fixture case also asserts the old generic labels and missing state controls
for all four metrics before comparing the repaired, gated matrix. The existing
required correction ratchet scans all app Swift sources with an empty baseline;
new external wrappers fail immediately. This also avoids a source-only test
being hidden by Turbo's package cache when only iOS source changes. The guard
is a source check, not proof of the accessibility tree or VoiceOver activation.

## Local evidence (Linux, 2026-10-25)

- Root `pnpm lint` and `pnpm typecheck` passed through the pinned bootstrap
  (`bash scripts/codex-setup.sh --run ...`). Root `pnpm test` initially passed
  with cached tasks. Fresh runs exposed existing five-second suite timeouts.
  The final single-worker run passed all 35 shared-lib files, registry checks,
  design-token tests and the web build; its web canvas replay timed out. The
  existing sequential web CI script then passed all 1,166 tests and three voice
  adapter cases. No timeout, assertion, coverage floor or CI setting changed.
- SwiftLint 0.65.1 with `--strict --no-cache` passed all nine changed Swift files.
  Linux skips five SourceKit-dependent rules, including custom rules; native
  strict lint remains required.
- Replacing DashboardMetricsSection with its original main source caused the
  ownership regression to fail on four external buttons. Restoring the candidate
  passed. That comparison used `--force` to execute tests instead of cached logs;
  the failing run also had two unrelated five-second test timeouts, and the
  restored candidate suite passed with fresh execution.
- Static launch UI and optical-grid audits passed (zero grid regressions).
- The dedicated guard behavior tests and the correction ratchet passed. The
  unrelated existing claims baseline retains eleven warnings.

## Native acceptance remains open

The native command could not start: `xcodebuild: command not found`. This host
has no iOS simulator, declared physical device, VoiceOver or Switch Control
session. No native compilation, execution, coverage, screenshots, motion receipt
or device accessibility acceptance is claimed. LYB-43 is not closed by source
checks. Existing large-text header scaling/hyphenation is outside this diff.

Run the existing native Unit and quality gates on the final commit. The new
unit cases live in UIAccessibilityContractTests, already in the real Unit target.
The new UI methods are in the registered UI target and its full UITests plan;
the quality runner's fixed UI subset does not automatically select new methods.
Explicitly qualify these additional selectors on the same final commit:

- `LogYourBodyUITests/LogYourBodyUITests/testMetricCardLegacyFixtureExposesTheMissingStateControl`
- `LogYourBodyUITests/LogYourBodyUITests/testMetricCardStateAccessibilityTreeAndActions`
- `LogYourBodyUITests/LogYourBodyUITests/testMetricCardAX3StateAccessibilityTreeAndActionsWithReduceMotion`
- `LogYourBodyUITests/LogYourBodyUITests/testMetricCardReducedMotionLoadingRemainsStill`

Retain xcresult trees and action counts for all four metrics and six states.
On a declared physical device, record model, OS, installed commit/build and gate
state. With VoiceOver, traverse forward/backward, activate each add/retry/
permission/details control once, verify the expected handler count/destination
and return focus, and verify loading has no action. Repeat with Switch Control.
Check loading and state transitions with Reduce Motion on/off, including toggling
it while the screen is mounted. At AX sizes confirm the hidden chart's latest
value, date/timeframe and source remain spoken, with one “No change”.

## Conflict repair (2026-10-26)

Merged origin/main at 1db992b00 without rebasing. The only conflict was the
correction ledger; the existing resolver retained both parents' receipts and
classified their union. Metric identity, state actions, fixture routing and
native test methods remain present after the merge.

Extended `scripts/correction-classifier.mjs` so a staging retry refuses unstaged
ledger edits, preserving both the working file and index. The new real-Git
regression failed against the previous resolver, then passed with all 11
classifier tests and 100% line, branch and function coverage. Used the extended
resolver's staging and read-only retry modes for this merge. The shared-lib
suite retains the existing required classifier coverage gate.

Local validation passed: the frozen dependency bootstrap, root `pnpm lint`,
`pnpm typecheck` and `pnpm test`, correction coverage and ratchets against
origin/main, and strict SwiftLint on all nine PR Swift files. Linux SwiftLint
skipped five SourceKit-dependent rules. The latest prior-head CI run
40220881168 passed and `gh run view --log-failed` returned no failed steps.
The merged commit still needs the repository's native CI; this host has no
`xcodebuild`, simulator, VoiceOver or Switch Control session.

GBrain write and readback for `lyb-43-pr1550-ledger-conflict-repair` both failed:
the local service at 127.0.0.1:7801 refused connection. Persistence is unverified.

The harness owns pushing and PR updates. Its PR body must include this line:

`Machine: built scripts/correction-classifier.mjs`

## Conflict repair refresh (2026-10-26, main c56aa3a48)

Merged `origin/main` into head `40b2ce541` without rebasing. Resolved the
classifier test conflict by retaining both parents' unstaged-receipt and
staged-marker regressions. Used `--resolve-merge . --stage` to retain all 79
correction receipts, then ran `--check-merge .` and the staging retry.
The metric implementation, native fixture and native test selectors are retained.

Extended the same machine for recurring repair class `fix-red-e3b0c44298`:
`--check-merge` now compares the working ledger with the index, matching the
staging retry. Its real-Git regression first failed because verification silently
accepted an unstaged receipt. Both commands now reject the edit while preserving
the working file and index. All 11 classifier tests passed with 100% line,
branch and function coverage. The existing required shared-lib suite and
pre-commit merge verifier execute the extension; no CI configuration changed.

Validation on this merged tree:

- `bash scripts/codex-setup.sh` passed with frozen dependencies and pnpm 10.34.1.
- `bash scripts/codex-setup.sh --run lint`, `--run typecheck` and `--run test`
  passed. Turbo executed the changed shared-lib tasks and reused unchanged tasks.
- The classifier's Node test command with 100% line/branch/function coverage
  thresholds passed; the new regression failed before the extension.
- Correction coverage and ratchets passed against `origin/main`; the metric
  control-owner ratchet has zero findings. The existing claims baseline retains
  eleven warnings.
- Strict, uncached SwiftLint passed all nine PR Swift files, with the same five
  SourceKit-dependent rules unavailable on Linux. `git diff --check` and
  `python3 scripts/repository_docs.py` passed.
- `gh run view 40393700166 --repo JovieInc/LogYourBody --log-failed` returned no
  failed steps; GitHub reported successful checks for pre-merge head `40b2ce541`.

`xcodebuild ... build-for-testing` could not start (`command not found`). Native
execution, coverage and device VoiceOver/Switch Control acceptance on the merged
commit remain for CI and the acceptance procedure above. Local Git mutations and
child-process checks required sandbox escalation. GBrain put and get for
`lyb-43-pr1550-ledger-conflict-repair` both failed with connection refused at
127.0.0.1:7801; writeback and readback remain unverified. No push or PR edit was
performed; the harness must add the machine line above to the PR body.
