# LYB-153 workout numeric scrub

The existing live training row and correction sheet use `TrainingNumericScrub`
when the `workout_numeric_scrub_v1` Statsig gate is enabled through the platform
analytics port. The initializer defaults to disabled; an absent gate leaves the
existing TextFields and RIR Stepper in place.

The primitive edits reported performance, never training prescriptions. It uses
the existing reps/load/RIR bindings into `TrainingSessionDraft`. Horizontal drag
changes gesture-local state; release writes the binding once. Logging and
correction still require their existing explicit actions and durable identities.
Pending submissions disable the controls. There is no new data store or network
path.

- Reps: 1–50, integer steps. RIR: 0–6, integer steps.
- Load: 0–500 canonical kg, displayed in the user's chosen kg/lbs unit.
  Conversion occurs at the input boundary. Unchanged pound displays never
  round-trip the stored kilogram value.
- Default input increments: 0.5 kg or 1 lb. The load menu offers 0.25, 0.5, 1,
  1.25, 2.5, 5 and 10 in the displayed unit, so users can select the increment
  available on their equipment. The training contract has no equipment increment
  or per-hand field; this control preserves its existing load convention and
  never multiplies a per-hand value. Tap entry accepts other decimal loads.
- Normal movement: 12 points per step. Moving 44 points up switches to 48 points
  per step without changing the current value. Moving 80 points down cancels the
  gesture. Haptics occur only when a snapped value changes; no flick momentum.
- Vertical scrolling wins directional recognition. UIKit gesture cancellation,
  scene interruption, disabling the control, changing units/rows or a changed
  binding discards provisional work. Numeric entry has explicit Done/Cancel.
- VoiceOver exposes adjustable and numeric-entry actions. Visible +/- targets
  are at least 44 points. Accessibility type stacks the live fields vertically.
  Drag updates have no animation, including with Reduce Motion enabled.

Rest is a bounded seconds configuration (0–3600, 5-second input steps) in unit
tests and the native preview only. **No live rest-timer adoption is included.**
LYB-116 owns the real editable rest-time contract; its owner must supply that
binding and authoritative bounds before adopting the primitive.

## Validation and remaining native acceptance

On the Linux implementation host:

- `corepack pnpm lint`, `corepack pnpm typecheck`, `corepack pnpm test`: passed.
  The test suite needed execution outside the sandbox after subprocess/socket
  operations failed with EPERM inside it. No checks were disabled.
- Strict SwiftLint on all six changed Swift files: zero violations. This Linux
  binary reports that five SourceKit-dependent rules cannot run on this host.
- Swift 6.2.1 syntax parsing: passed for all six changed Swift files.
- Nine `TrainingNumericScrubTests` passed in an isolated Linux SwiftPM harness
  using the production policy, unit-conversion source and canonical load parser.
  Only the preference-key constant was stubbed. This does not execute SwiftUI,
  UIKit, Core Data or the native app runner.
- Regression proof: `testFastAndSlowSamplesReachTheSameValueWithoutFlickOvershoot`
  failed with slow sampling producing 15 rather than 16 before step accumulation
  was normalized, then passed after the fix.

The Xcode project includes the new unit and UI suites in their real targets.
Two draft integration tests cover pre-release journal isolation, offline replay,
canonical relaunch readback, correction identity and duplicate-submit prevention.
Five XCUITests cover the three live dimensions, fast/slow drag, cancellation,
keyboard entry, pounds-to-kg readback, background interruption, offline retry,
large type, Reduce Motion and reachable safe-area controls. Native previews show
all four primitive dimensions, including an accessibility-size fixture.

**These native integration/UI suites have not run on this Linux host.** Before
rollout, run the repository's `bundle exec fastlane ios ci_test_unit` lane and
the UI suite through `bundle exec fastlane ios test_ui` on its supported
macOS runner, preserving current coverage gates and exact-commit receipts.
VoiceOver behavior, interruption during an active touch, rest adoption, 200%
Dynamic Type and hitch-free operation on a supported real iPhone remain native
acceptance work; portable tests and syntax parsing do not establish those facts.

The harness owns commit pushing, PR creation and merge. No push, PR operation,
Statsig rollout or release was performed during implementation.

## Merge repair, 2026-10-26

Merged `origin/main` at `2e9187a7f2775d3abdfaf0f57af7cad1cc9d26dc` without
rebasing. Retained numeric scrub alongside training progress, undo and canonical
saved-set callbacks. The composed Xcode project retains both parents' Swift
references; its diagnostic dependency pin and repository source map are current.

Extended `scripts/correction-classifier.mjs` with `--merge` and used it on both
immutable parent ledgers. The normal shared-lib suite runs the new CLI regression:
it failed against the old CLI, then passed with 100% line, branch and function
coverage. Distinct receipts survive, contradictory duplicate evidence fails
without writing, and repeated merges preserve bytes. Recorded the correction in
the existing ledger and documented the command in the ledger guide.

Repair validation on Linux:

- `corepack pnpm install --frozen-lockfile --prefer-offline`, `corepack pnpm lint`,
  `corepack pnpm typecheck`, `corepack pnpm test`: passed (pnpm 10.34.1).
- `python3 -m pytest -p no:cacheprovider scripts/tests/test_runner_routing.py -q`:
  44 passed. All seven diagnostic dependency hashes match the merged source.
- Strict SwiftLint with `--no-cache` on the six PR Swift files: zero violations;
  the five SourceKit-dependent rules remain unavailable on this host.
- Correction coverage against both merge parents, guard-reference validation,
  correction ratchets, URL drift, repository source parity and `git diff --check`:
  passed. The existing 11 web-claims baseline findings remain warnings.
- `gh run view 40172790796 --repo JovieInc/LogYourBody --log-failed`: no failed
  logs; the existing head's reported checks passed. The repaired head still needs
  the required macOS native checks; no Xcode runtime receipt is claimed here.

The harness retains push and PR ownership. Its PR-body handoff line is
`Machine: built scripts/correction-classifier.mjs`. GBrain query, write and
readback could not connect to its local service; persistence is unverified.

## Subsequent merge repair, 2026-10-26

Merged `origin/main` at `ae6cf8e23f63606b77c10abce547a14972d4fb19` without
rebasing. The only conflict was the correction ledger. Extended the existing
classifier with `--resolve-merge repository` and used
`node scripts/correction-classifier.mjs --resolve-merge .` to read both Git
conflict stages and retain all 53 receipts. Updated the existing repair receipt
and command guide. Native source and target membership are unchanged from the
PR parent `83508799ed311e42400c133d42cc3c7d651d4cf8`.

The new regression creates real conflicting Git branches. It failed against the
previous CLI's usage check, then passed with the extension. It verifies receipt
retention, contradictory-evidence rejection without writes, idempotence,
missing-stage refusal, paths containing spaces, and preservation of the index,
parents and unrelated edits. All 11 classifier cases passed with 100% line,
branch and function coverage through the existing required shared-lib runner.

Commands run for this repair on Linux:

- `corepack pnpm install --frozen-lockfile --prefer-offline`;
  `corepack pnpm lint`; `corepack pnpm typecheck`; `corepack pnpm test`: passed.
- `node --test --experimental-test-coverage
--test-coverage-include=scripts/correction-classifier.mjs
--test-coverage-lines=100 --test-coverage-branches=100
--test-coverage-functions=100 scripts/correction-classifier.test.mjs`: passed.
- `node --test .github/scripts/detect-changes.test.mjs`: 32 passed.
- `node packages/shared-lib/scripts/correction-coverage.mjs --base-ref
83508799ed311e42400c133d42cc3c7d651d4cf8` and the same command against
  `ae6cf8e23f63606b77c10abce547a14972d4fb19`: passed.
- `node packages/shared-lib/scripts/guard-reference.mjs --base-ref origin/main`;
  `node packages/shared-lib/scripts/correction-ratchet.mjs --base-ref origin/main`;
  `python3 scripts/repository_docs.py`; `git diff --check`: passed.
  The 11 existing claims findings remain baseline warnings.
- `gh run view 40172790796 --repo JovieInc/LogYourBody --log-failed`: returned
  no failed logs. That run covers an earlier PR head, not this repaired commit.

Tests and Git-based validation needed execution outside the sandbox because its
subprocess restrictions cause EPERM. Xcode is unavailable on this host; required
native execution remains for CI. The harness owns pushing and the PR-body update
with the machine line above. GBrain's local service remains unavailable, so
durable write and readback are unverified.

## Merge retention guard repair, 2026-10-26

Merged `origin/main` at `d25896651e9bd5c74c3fd65382987dd058c5c2da` without
rebasing. Used `node scripts/correction-classifier.mjs --resolve-merge .` for the
only conflict, retaining all 54 correction receipts. Extended that same machine
with `--check-merge .` and used it to verify the staged result against both
immutable parents. Pre-commit now runs the read-only check for every merge,
including when the ledger has no diff against `HEAD`.

The regression failed on the previous CLI's usage check and now passes. It
rejects lost receipts from either parent, stale classification, malformed staged
JSON and missing staged guard anchors while preserving the index, working tree,
parents and unrelated edits. The existing normal shared-lib runner executes all
11 classifier cases with 100% line, branch and function coverage. Its wrapper
now uses the existing child process's 30-second deadline after the expanded suite
exceeded Vitest's default five seconds under concurrent execution.

Commands run on Linux:

- `corepack pnpm install --frozen-lockfile --prefer-offline`,
  `corepack pnpm lint`, `corepack pnpm typecheck`, `corepack pnpm test`: passed.
  Turbo reused unchanged package tasks; shared-lib tests executed for this repair.
- `node --test --experimental-test-coverage
--test-coverage-include=scripts/correction-classifier.mjs
--test-coverage-lines=100 --test-coverage-branches=100
--test-coverage-functions=100 scripts/correction-classifier.test.mjs`: passed.
- `node scripts/correction-classifier.mjs --check-merge .`: passed against the
  staged ledger and guards. Correction coverage also passed with `--base-ref`
  set separately to `c32f8c69961b221240a0292051bb0a9874ee306b` and
  `d25896651e9bd5c74c3fd65382987dd058c5c2da`.
- Guard references, correction ratchets, URL drift, `python3 scripts/repository_docs.py`,
  `bash -n .husky/pre-commit`, and staged/worktree `git diff --check`: passed.
  The existing 11 claims-baseline findings remain warnings.
- `gh run view 40301840766 --repo JovieInc/LogYourBody --log-failed`: returned
  no failed logs for the supplied PR head. Required checks must run on the new head.

Git/subprocess checks required sandbox escalation. Native sources, target
membership and the diagnostic workflow are unchanged from the supplied PR head;
Xcode is unavailable here and native acceptance remains unverified. The worktree
started detached with the PR branch in use elsewhere, so the local repair uses
`fix/lyb-153-pr1544-merge-repair`. The harness owns pushing and the PR-body update:

`Machine: built scripts/correction-classifier.mjs`

GBrain query, write and same-slug readback could not connect to its local service;
durable persistence remains unverified.
