# Workout reconciliation (LYB-249)

This slice supplies policy, an observable view model and local persistence. It adds
no views, location monitoring, HealthKit workout import, training prescriptions or
set logging. The attendance-states dependency is absent from this branch.

The attendance owner should create `WorkoutReconciliationViewModel` with a
`CoreDataWorkoutReconciliationStore` using the app's persistent container and a live
context closure. Map the attendance system's `probable` state to
`hasProbableAttendance`; supply the current account, gym, permission and log status.
Refresh when those inputs, the feature gate or the local calendar day change. The
default gate lookup uses the platform analytics port and the positive Statsig gate
`workout_reconciliation_v1`; missing config leaves the feature off. Presentation and
attendance event wiring remain with the parent slice.

`prompt.question` contains the specified copy. The first offer saves an account/day
suppression marker before publishing. Refresh can retain that same visible prompt;
another model, another gym or relaunch cannot offer a second question that day.
Ignoring clears the prompt without writing a response or session. The marker has
no gym, attendance verdict or timestamps.

`confirm()` saves an attendance-only `ReconciledWorkoutSession`, separate from
engine-owned `TrainingSession` prescriptions. Both timestamps default to nil and
only explicit user input may supply them. There is no passive timestamp input or
set-writing API. `setLevelVolume` is nil; duration requires two valid, ordered,
user-confirmed timestamps. `deny()` saves a denial without a session. Each response
rechecks live context, day and saved response before writing.

Core Data V5 adds only `CachedWorkoutReconciliationDay`, retaining the existing
entities unchanged. Its payload stores suppression, explicit responses and
confirmed sessions locally. It is included in account deletion. Cloud workout sync
is outside this slice.

`WorkoutReconciliationPromptTests` is in the native test target and is not excluded
by the Unit plan. It covers the requested five-state table, verified-only session
fields, response freshness, feature gating, local-day boundaries, persistence
reopening, write failures and V4 migration. Native execution and coverage require
the repository's macOS Unit runner; Linux lint and JavaScript checks do not prove
those cases pass. Real-device TestFlight evidence remains with LYB-175.
