# Curated exercise and setup selection (LYB-176)

The native workout's **Movement response and alternatives** flow reuses the
existing catalog, LYB-114 observations and revision-checked workout action.
It offers at most one different exercise and one same-exercise setup for
non-pain back/trunk fatigue. `setupOf` establishes movement identity; shared
muscle targeting does not make two exercises the same movement.

The existing 25 curated catalog metadata entries bound this first release:
upper chest, lateral delts, lats, arms and lower body. There is no new library,
biomechanical simulator or numerical SFR score. Expected qualitative trunk
requirements remain separate from observed trunk fatigue and do not measure
spinal loading or establish individual safety. Metadata and ROM/setup caveats
are displayed from the catalog, including preacher arm support versus torso
support, floor restrictions, bench clearance and cable placement.

## Review and approval

`POST /api/auth/mobile/training/v1/alternatives` is authenticated, rate-limited,
subject-scoped and uncached. It reads existing feedback and returns a proposal;
it does not write records or alter an exercise. The request identifies the exact
session/variant and explicitly confirmed equipment for the current gym. Gym
names never establish inventory. The previously saved gym/setup can be reused
explicitly, then corrected for this visit.

`suggestAlternatives(..., { allowTrials: true })` is the native policy: one
explicit current fatigue observation can produce supported **trials**, without
requiring an already successful swap. The default `allowTrials: false` preserves
the earlier LYB-256 repeated-evidence policy. Both use catalog equipment and
concern exclusions. Trials stay within the curated set and current program
exclusions. A candidate's latest adverse response disqualifies it. Known
symptoms in the current session stop the review until corrected; missing values
never establish absence of symptoms or fatigue. A belt request adds no evidence.

The user checks the station, clearance, cable line and comfortable range before
approving an option. The server recomputes eligibility from saved observations
and the submitted current inventory; arbitrary candidate IDs are rejected.
Approval uses the existing workout action CAS, event ID, ownership and training
admission checks. It preserves completed set identities and moves only remaining
sets to the replacement, with a new starting load. It never removes a muscle's
whole workload. Replay is idempotent; a stale revision fails closed.

An approved event stores the previous prescription, exact variant, gym,
equipment, exclusions and optional setup note in the existing session record.
`restore_swap` restores the previous prescription before any replacement sets
are logged. It retains the completed original sets and records the rollback.
No extra database collection or migration is needed; training erasure already
owns the containing session/feedback records.

## Observations and subsequent prescriptions

The occasional movement check-in starts every field as unreported. Target-muscle
quality, joint discomfort, trunk fatigue, general exhaustion, stability and
meaningful ROM restriction remain separate optional observations. ROM, gym,
equipment and setup notes extend `TrainingSetContext`; quality and stability
extend `TrainingFeedback`. Existing source identity, append-only correction,
feedback journal and retry handling are retained. Exercise-scoped observations
do not silently supersede another exercise or the session summary.

`learnedExerciseSwaps` feeds the existing block-swap application only after the
user approved the choice and two independent sessions explicitly report zero
joint discomfort and trunk fatigue, stable execution, good target-muscle quality
and no meaningful ROM restriction. This is a conservative product rule, not a
clinical threshold or causality claim. One session, missing fields, copies,
uncertain/historical reports and corrections cannot establish repeated response.
New adverse feedback or a changed gym/inventory prevents retention. The variant
uses its own performance history, never the original movement's load. Undo
retracts the learned choice; no new training numbers come from conversation.

Pain or concerning symptoms return no alternatives. The native flow records the
observation and pauses the movement using the existing pain action. Its symptom
hold remains visible even when the separate readiness UI gate is off. Copy says
to avoid training through pain and seek medical evaluation for persistent,
worsening or neurologic symptoms. It provides no diagnosis or guarantee.

The accepted [LYB-257 pain-guidance decision](../product/exercise-swap-pain-guidance.md)
records the exact replacement copy, any-pain trigger and explicit pain-gone
requirement. Its created `exercise_swap_pain_guidance` UI/logic slice owns
implementing that wording and resolution flow; this guide's existing runtime
description does not establish that the follow-up is implemented.

## Rollout and evidence

Both server switches must be true: `LYB_HYPERTROPHY_COACH_API_ENABLED` and the new
default-off `LYB_EXERCISE_SELECTION_ENABLED`. Native also requires the existing
coach rollout and the `exercise_selection_v1` Statsig gate through the internal
analytics port. This change does not enable either rollout.

Regression coverage includes first-report distinct-exercise/setup proposals,
standing fatigue/supported response, floor ROM, alternate gym inventory, belts,
shoulder pain and neurologic symptoms, missing feedback, single-session
uncertainty, forged/stale approvals, partial-work preservation, replay, rollback
and corrections. Native regression source checks separate/unknown dimensions
and authenticated review/context matching in `TrainingProgressTests`.

The initial regression failed with the original helper (`not_enough_evidence`
instead of `suggested`) and passed with the trial path. Local JS checks and
Swift static audits are recorded in the handoff. This Linux host has no Xcode:
native execution, coverage, installed-build interaction and TestFlight
certification remain unverified. Required native gates must run on the final
commit and installed-build evidence must be supplied before rollout or a claim
that LYB-176 shipped. The harness owns push, the one PR and merge operations.

Machine: built `apps/web/src/lib/training/selection.ts` by extending the existing
alternatives, observation, action and block-swap mechanisms.

### Local receipt (2026-10-30)

Node 22.23.2 and Corepack pnpm 10.34.1 were used. A temporary PATH shim ensured
nested `pnpm` calls used that same pin; the host's unrelated pnpm 9.15.4 was not
used for the successful root checks.

- `pnpm lint` and `pnpm typecheck`: passed across all applicable workspaces.
- `pnpm test`: passed, including the production web build, 157 web suites / 1,505
  Jest cases, all three voice adapter smoke cases, 48 shared-lib files / 207
  cases and their 122 Node policy cases. Web coverage was 56.50% statements,
  58.36% branches, 59.47% functions and 58.05% lines; existing floors passed.
- Scoped alternatives, selection, service and native API Jest run: 106 cases
  passed before the additional API cases; the subsequent full suite includes
  those cases. The first-report regression failed with the original production
  helper and passed with the changed helper.
- `pnpm lint:knowledge`: passed with the existing reviewed web-copy warnings.
- Correction coverage and the correction ratchet against `origin/main`: passed.
- `python3 scripts/repository_docs.py`: passed after refreshing the Xcode-project
  fingerprint; no shared canon or CI configuration changed.
- `node scripts/ios/swift-arch/guard.mjs`: no new violations (542 existing).
- Strict SwiftLint with `--no-cache` on all seven changed Swift files: zero
  violations. This host prohibits SourceKit-dependent rules, so this is partial
  lint evidence rather than complete native qualification.
- `xcodebuild ... build-for-testing`: could not execute (`xcodebuild: command not
found`). The new native observation serialization, authenticated review and
  offline-journal regressions have not executed here. No native coverage,
  simulator/device interaction or TestFlight receipt is claimed.

The first sandboxed root test attempt failed on child-process `EPERM` errors.
The successful full runs allowed the existing subprocess fixtures without
changing tests, thresholds or timeouts. GBrain query, write to
`lyb-176-exercise-selection-integration`, and same-slug readback all failed with
connection refused at `127.0.0.1:7801`; the durable write/readback gap remains.

## Approval presentation (LYB-300)

`apps/web/src/components/training/ExerciseSwapApproval.tsx` is the UI-only review
component for a completed selector result. It renders the two nullable selector
slots without inspecting feedback, inventory, ROM, or eligibility. The caller
supplies catalog display names, the existing `evaluateDeload` pain-policy result,
and any already-established constraint reason codes (`blocked_rom_or_clearance`,
`missing_station`, `belt_does_not_clear_symptoms`). Both supported selector reasons
explain that support may reduce trunk demand without implying zero spinal load.
Trial reasons explicitly describe an exercise or setup to try; they do not claim
an established response. The copy map must cover every engine reason at compile time.
Constraint reasons explain withheld floor setups, hidden missing stations, and
that a belt does not clear persistent symptoms. A `pause_session` result renders
only the policy's exact explanation, even if candidates were also supplied.

Choosing a radio option never changes the prescription. Only **Approve swap**
calls `onApprove` with the exact selected variant ID. The host connects that
callback to the existing swap persistence API, rejects failed receipts, and
updates its active prescription from authoritative readback after success. The
component prevents repeated submissions while saving and permits an explicit
retry after a failed save. **Keep current exercise** closes the review locally
and optionally notifies `onReject`; it never invokes the persistence callback.

The host must supply an account/session/revision-scoped `reviewId` and change it
when replacing the reviewed context. A new review or a policy pause clears the
prior choice. `enabled` defaults off and is supplied by the host's existing
training gates. This presentation slice adds no route, native runtime activation,
selector rule, persistence endpoint, or change to LYB-114. Wiring into the native
training surface remains in LYB-176; the React tests prove the component contract,
not an installed iOS interaction or a real-provider write.

The existing web Jest discovery includes the approval UI tests and reason
snapshot in CI; the existing root typecheck includes the component. Scoped run:

```bash
pnpm --filter logyourbody test:watch --watch=false --runInBand --runTestsByPath src/components/training/ExerciseSwapApproval.test.tsx
pnpm typecheck
```
