# Training progress history (LYB-110)

`GET /api/auth/mobile/training/v1/progress` returns
`{ version: 1, progress: TrainingProgress }`. It uses the same
`loadTrainingRecords` and `summarizeTrainingProgress` as the LYB-108 MCP
`get_training_progress` tool. Authentication, the existing
`LYB_HYPERTROPHY_COACH_API_ENABLED` switch, account scoping, request limits and
`Cache-Control: no-store` apply. An unenrolled/revoked account receives an empty
summary with `enrolled: false`; a storage failure returns a sanitized 503.
The endpoint never starts, completes, reconciles or changes a session.

The existing summary fields remain compatible: completed-session count,
sets in the last seven days, exact-variant exercise summaries, last recorded
session's sets and heaviest recorded set. Invalid or future completion times
do not count as performed sets. Historical sets retain their server ID,
session/variant identity, ordinal, corrected reps/load/RIR, completion time,
revision and correction audit. Heaviest uses current corrected values rather
than superseded values.

The additive `sessions` readback retains program setup/revision and block IDs,
explicit saved status, original and current prescriptions, interruption events,
sets and feedback. A skip remains an explicit event even when its movement was
removed from the current prescription and has no sets. Missing logs are never
classified as skips or completion. Feedback retains original wording, source,
observation identity/time, correction links, set context and interpretations.
Superseded feedback stays in the session audit; `latestCheckIn` selects an
observation that has not been corrected.

Native history is behind the default-off Statsig gate
`training_progress_history_v1`, inside the existing coach gate. It uses the
platform feature port, existing theme and Jovie spacing, Dynamic Type fonts,
and the current Now/Up Next cards. Rows say “Last recorded” because the latest
record may belong to the workout in progress. Bodyweight and explicit zero
load remain distinct. History refreshes on reopening, set acknowledgments,
corrections, interruption events and feedback acknowledgments. Loading and
retry are independent of workout controls; account ownership is checked before
and after reads, and older responses cannot replace a newer refresh.

`ProgressReviewCard` places saved results and reported recovery/tolerability
alongside the existing `/next` engine receipt. It renders engine-provided
actions, and shows before/after and rationale only for meaningful changes.
Confirmation-required proposals remain proposals. The client does not generate
prescriptions, infer growth from pump or reduced trunk fatigue, compute a
readiness score, or apply a repeat block. Exact successful variants remain
addressable in history; historical temporary priorities are not copied or
renewed. A repeat-block engine must evaluate priority expiry and obtain renewal
through its existing revision flow, using these original identities as evidence.

Read-path ownership was coordinated on LYB-108 and layout on LYB-124, using its
compact native card contract. This change adds no competing MCP implementation,
programming engine, review-approval operation or workout surface.

Regression coverage lives in `progress.test.ts`, the authenticated training
route tests and `TrainingProgressTests`. UI cases
`testTrainingHistoryShowsRecordedPerformanceAtAccessibilityTextSize` and
`testUnavailableHistoryLeavesSetLoggingUsable` extend the existing production-view
DEBUG fixture, with synthetic history callbacks. Those callbacks do not certify
the deployed API. Exact-head native Unit execution/coverage, UI screenshots,
VoiceOver and an installed-build replay against deployed services require the
repository's macOS/native runner; they were unavailable on the Linux host.
Keep the native gate off until those receipts pass.
