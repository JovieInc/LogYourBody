# Outcome feasibility (LYB-270)

`OutcomeFeasibility(now:thresholds:).classify(outcome:history:)` is a pure function
over the persisted `DatedOutcome` and comparable, canonical-unit measurements.
The caller supplies the clock. It returns only `ok`, `unsafe`, `impossible`,
`expired`, or `noData`; it does not generate wording, prescriptions, or new dates.

Classification checks, in order:

1. A valid deadline at or before `now` is `expired`, regardless of targets,
   thresholds, or history. Dates use the same strict UTC calendar-date parser as
   storage and the same midnight deadline as `DatedOutcome.planInputs`.
2. Invalid outcomes or missing/incomplete/non-finite metric-specific bounds are
   `unsafe`. All four bounds are required, including for maintenance or no data.
   Target bounds must be positive and ordered; signed weekly bounds include zero.
3. A target outside its supplied inclusive bounds is `unsafe`.
4. No usable matching measurement, or conflicting values at the latest usable
   timestamp, is `noData`. Future, non-finite, non-positive and other-metric
   measurements are excluded. Equal duplicates and history order have no effect.
5. The mathematical requirement `(target - latest measurement) / weeks remaining`
   is `impossible` outside the supplied inclusive signed weekly bounds, otherwise
   `ok`. Non-finite arithmetic fails closed to `unsafe`. No trend is extrapolated.

The pinned Jovie `lyb-launch-contract/v1` fixture used by the
[backward planner](../architecture/backward-planner.md) defines `launch.safety`
but contains **no feasibility cases or numeric thresholds**. This was also true
of Jovie main when implementing this slice. There are no production defaults;
without reviewed policy every unexpired outcome returns `unsafe`. The decision
issue must supply approved thresholds before integration can admit an outcome.
The parent must also enforce eligibility, provenance/freshness, and the existing
default-off dated-outcome gate before exposing this capability.

`OutcomeFeasibilityTests` reads the bundled contract and asserts its missing
policy fails closed for every supported metric. A changed contract shape fails
the test so new policy/cases must be reconciled explicitly. Separate arithmetic
examples use test-only bounds to cover all five results, each missing threshold,
malformed policy/data, expiry precedence, loss/gain/maintenance boundaries,
deadline edits, clock validity, metric isolation and deterministic history use.
These examples are not contract-provided cases or approved physiological policy.
No current upstream classification-case parity can be claimed because those
cases do not exist in the fixture.

Both Swift sources are registered in the existing Xcode targets; the XCTest class
is not skipped by the Unit plan. Execution and native coverage require the real
macOS runner. Device/TestFlight evidence remains with LYB-183.

Local verification on the implementation Linux host:

- `bash scripts/codex-setup.sh --run lint` and `--run typecheck` passed via Turbo
  cache; `--run test` passed after rerunning outside the sandbox's subprocess
  restrictions (8 tasks, 7 cached; shared-lib executed 206 Vitest and 122 Node tests).
- `bash scripts/codex-setup.sh --run lint:swift --no-cache` passed across 519 files.
  This Linux SwiftLint build skips five SourceKit-dependent rules; CI must run the
  full native toolchain.
- `python3 scripts/ios/test_training_rest_project.py` passed, including native test
  membership and model graph checks. `git diff --check` passed.
- Swift 6.0.3 in Swift 5 language mode compiled the unchanged model and classifier
  and ran all 11 `OutcomeFeasibilityTests` methods successfully using an isolated
  Linux XCTest launcher in `/tmp`. Its only supporting app declaration,
  `TrainingPlanningInputs`, was copied verbatim from `TrainingService.swift`.
  Two temporary source mutations (admitting missing policy, moving expiry after
  data checks) were rejected by XCTest assertions; restored source passed again.
  This is pure-function evidence, not an iOS build or native coverage receipt.
- The scoped `xcodebuild ... -only-testing:LogYourBodyTests/OutcomeFeasibilityTests test`
  attempt could not execute because Xcode is unavailable. No native test result or
  coverage is claimed.

GBrain was unreachable from the sandbox. Retrying outside the network sandbox
persisted `engineering/lyb-270-outcome-feasibility`; reading the same slug back
verified the saved finding. Optional repository write-through reported
`repo_not_found`; the GBrain page itself was saved and read successfully.
