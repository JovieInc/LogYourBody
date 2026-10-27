# Native training cards v1 (LYB-124)

The native consumer is canonical chat's training surface in `MainTabView.swift`.
It reads owned training objects independently of the transcript and mounts the
existing workout and delegated-program views. No web workout surface, MCP
implementation, model-generated view tree, or UI-runtime migration is added.
PR #1210 is already merged; LYB-108's MCP and LYB-109's load policy remain owned
by their existing implementation. The existing onboarding questions, safety
consent, Jovie theme, tokens, and plan service remain canonical.

## Closed component and action contract

`TrainingService.swift` owns the versioned `TrainingCardReference`,
`TrainingCardAction`, and `TrainingCardAdapter` types. The properties are
`{version: 1, component, objectId, revision, exerciseId?}`. `objectId` must be a
domain UUID, revision is a nonnegative integer, and only ExerciseSwapCard admits
(and requires) a catalog exercise ID. An action is
`{reference, name, alternativeId?}`; only `swap` admits/requires an alternative.
Unknown versions, components, action names, properties, invalid IDs, and
component/action combinations are rejected while decoding. There is no code,
HTML, URL, script, vendor-view, or expression property.

| Component            | Referenced domain object / revision               | Approved actions              | Owned native view                                                                  |
| -------------------- | ------------------------------------------------- | ----------------------------- | ---------------------------------------------------------------------------------- |
| MesoPlanCard         | Committed program revision UUID / canvas revision | expand, adjust                | Compact card → existing delegated weekly program sheet                             |
| PlanChangeCard       | Saved proposal UUID / proposed canvas revision    | expand, adjust, apply, reject | Reason, summary, expandable engine diff and existing steering inputs               |
| WorkoutSessionCard   | Session UUID / execution revision                 | expand, logSet, correctSet    | Existing coach card, persistent chat dock control, live workout and set navigation |
| ExerciseSwapCard     | Session UUID / execution revision + exercise ID   | swap                          | Eligible engine alternatives, exact setup, prescription and tradeoffs              |
| TrainingFeedbackCard | Session UUID / execution revision                 | feedback                      | Existing distinct recovery check-in and durable observation receipt                |
| ProgressReviewCard   | Session UUID / execution revision                 | review                        | Existing recorded set/session/check-in history and bounded engine review           |

`ApprovedTrainingCard` in `TrainingProgressViews.swift` rejects invalid references
before mounting compiled content. The reference never supplies numeric training
values. Those come from the authenticated domain object loaded by the existing
service. UI actions compare the originating reference with current state and
account ownership; writes require local writable state. This is supplemental
admission: first-party APIs still enforce authentication, consent, owner
incarnation, eligibility and revision checks. Set values/corrections use the
existing typed set requests and compound session/exercise/set identity.

Apply/reject calls the existing saved-proposal decision operation. A matching
proposal/request/status receipt, committed revision readback and equality with
the reviewed native plan are required before refreshing the executable next
session. Adjust creates another reviewed proposal through the same service. It never directly rewrites a program.

A selected swap uses the existing revisioned `/action` command with
`{kind: "swap", exerciseId, replacementExerciseId}` and the same event UUID on
retries. The server revalidates the exact engine alternative, rejects movements
with recorded work, and persists one substituted event without rebuilding the
other exercises or the weekly plan. Setup descriptions are projected from the
reviewed catalog in native API responses; no new physiological calculation or
fatigue/readiness score is introduced.

json-render is not adopted: this change has an owned SwiftUI consumer, and no
supported JavaScript rendering consumer requires it. The shared vocabulary is
not a drop-in Swift integration or justification for migrating the native UI.

## Persistence and rollout

Native card behavior requires both default-off Platform/Statsig gates
`hypertrophy_coach_v1` and `native_training_cards_v1`. Plan operations additionally
retain `delegated_programming_v1`; history retains `training_progress_history_v1`.
The existing server training/delegated-programming flags still apply. This PR
does not enable a gate or modify admission, workflow configuration or release
policy.

The existing account-isolated `TrainingDraftStore` also stores the active
server-returned session with atomic file protection and backup exclusion. Chat
can reopen it before a network request finishes or while offline. Transcripts
and LLM requests do not own this state. Revocation/deletion's existing purge
removes both journal and cache. A delayed local receipt cannot replace another
active session, regress an execution revision, remove another acknowledged set,
or downgrade a corrected set. Server responses remain authoritative.

Workout set navigation can select another unrecorded or pending set without a
chat round trip. A pending row keeps its exact original request, remains marked
pending, and retries with the same identity and values. Recorded rows open the
existing correction flow. Closing the new workout surface remains available
while a request is pending. Feedback remains a separate observation journal;
review displays recorded results and meaningful engine changes only.

## Evidence boundary

Linux can run deterministic API tests and SwiftLint's available rules. It cannot
supply Xcode execution, coverage, VoiceOver behavior, screenshot review or an
installed-build receipt. The new XCTest cases live in the existing
`TrainingSessionDraftTests` and `DelegatedTrainingTests` targets; the UI regression
`testApprovedCardsNavigateOfflineAndRetainPendingIdentityAfterRelaunch` uses the
existing isolated native fixture, includes accessibility XXXL and attaches
screenshots. Synthetic UI transport is a wiring fixture, not real-provider or
seven-scenario certification. No target membership, diagnostic trust pin or
required native selector is changed.

The API regression fails before named swap admission (HTTP 400) and passes with
the change; it checks exact selection, persisted readback, an unchanged remainder,
owner isolation, duplicate-event identity, stale revisions and rejected unknown
or generated-code actions. Existing delegated-programming tests retain the
request → saved revision → workout → controller loop. Native tests add strict
schema/action admission, both default-off gates, committed apply readback (including
a deliberately empty/no-op saved program with a matching revision receipt),
offline cache/journal recreation, delayed-session receipt and disk-write failure.

All of the following installed-build receipts remain **UNVERIFIED** until the
existing LYB-64 authority executes them on the exact built/installed head:

| LYB-107 release scenario                  | Required installed-build interaction and durable readback                                                            |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1. Biceps priority / reduced trunk demand | Inspect diff/reasons → apply → saved revision → actual session matches, with other goals/schedule/equipment retained |
| 2. No cables / EZ bars                    | Generate, revise, swap and adapt while the hard exclusion persists                                                   |
| 3. Bench unavailable                      | Inspect eligible exact alternatives and tradeoffs, select one or show a constraint conflict                          |
| 4. Correct 12 to 10 reps                  | Select the existing set, correct it and verify identity/revision/audit rather than a second set                      |
| 5. Offline termination / reconnect        | Log locally, navigate, terminate, reopen offline, reconnect and verify one stored set                                |
| 6. Shoulder discomfort                    | Pause/review that movement and verify the safety boundary rather than routine progression                            |
| 7. Next block                             | Expire temporary priority unless explicitly renewed; retain durable preferences; missed work remains incomplete      |

The native runner must also certify loading, empty, unavailable, stale, pending,
retry, saved and corrected states; Dynamic Type, VoiceOver and navigation during
slow/offline chat; and ordinary, offline/relaunch and corrected/interrupted full
sessions. Retain exact commit/build/device/fixture, screenshots, interactions,
program/set/history/next-prescription readbacks and deliberate-red no-op-plan,
lost/duplicate-set and constraint fixtures under LYB-64. Source tests do not close
LYB-107/124 or LYB-64, and no installed-build acceptance is claimed here.

## Local execution for this change

Using the source-pinned Node 22.23.2 / pnpm 10.34.1 through
`bash scripts/codex-setup.sh --run`:

- `pnpm lint`, `pnpm typecheck`, `pnpm product:check`: passed.
- `pnpm --filter logyourbody test:ci`: 126 suites / 1,176 tests passed, plus
  all three voice-adapter tests. Local IPC was needed outside the sandbox.
- Scoped `swiftlint lint --strict --no-cache --config apps/ios/.swiftlint.yml`
  on every changed Swift file: zero violations. SourceKit-dependent rules were
  unavailable on Linux; this is not a full native lint or compile receipt.
- `python3 scripts/repository_docs.py` and `git diff --check`: passed.
- `pnpm test`: attempted. The sandbox first refused the voice runner's IPC;
  the rerun reached an unrelated 5-second timeout in the existing
  `MesocycleCanvasBoard.test.tsx` replay. The same full web suite passes under
  the existing sequential `test:ci` command. No timeout or gate was weakened.
- GBrain search, write to `lyb/native-training-cards-v1`, and readback all failed
  to connect to the local service at `127.0.0.1:7801`. Persistence is unverified.

There is no local Swift compiler/Xcode runner or installed native build on this
host. Native test execution, native coverage and all installed-build acceptance
remain pending the existing required runner and LYB-64 certification.
