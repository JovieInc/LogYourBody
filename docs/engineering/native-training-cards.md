# Native training cards (LYB-124)

Schema version 1 names six approved components: `MesoPlanCard`,
`PlanChangeCard`, `WorkoutSessionCard`, `ExerciseSwapCard`,
`TrainingFeedbackCard`, and `ProgressReviewCard`. The shared rules live in
`apps/web/src/lib/training/native-card-contract.ts`. The iOS adapter in
`NativeTrainingCardContract.swift` projects durable training records into that
contract and renders them with owned SwiftUI views.

json-render is not a supported consumer. It has no SwiftUI runtime here, so
this contract is not a drop-in renderer or a runtime migration. Unknown
components, invalid durable IDs, mismatched owners, invented readiness or
fatigue scores, and generated code are rejected. A chat transcript can only
echo a card that already exists for the signed-in account. It cannot create
one.

Plan apply, adjust, and reject call the existing saved-revision operation.
Swaps call the existing session swap endpoint and only offer alternatives
already on the exercise. The active session snapshot is stored on device by
owner, so the workout card can reopen across navigation and relaunch. Logging
stays enabled when chat is busy or unreachable. The native surface is behind
the default-off platform gate `native_training_cards_v1`, inside
`hypertrophy_coach_v1`.

This change does not add a web workout app or a second MCP server. Installed-build
screenshots, VoiceOver, and the LYB-64 / LYB-107 device certification still
require the repository's macOS native runner. Keep the gate off until those
receipts pass.
