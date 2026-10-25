# Training save and recovery contract

The mobile `/api/auth/mobile/training/v1/next` response includes
`session.loggedSets`, an array of the authenticated subject's acknowledged sets
for that session and program. Each set contains `sessionId`, `exerciseId`,
`setNumber`, `reps`, nullable `loadKg`, and `rir`, plus server record metadata.
The iOS field is optional so responses from older servers remain decodable.
Restored sets keep their saved values and cannot be submitted again from the
live-session view. Unsaved edits and pending submissions use the account/session-scoped device journal.

Set and recovery-feedback requests report HTTP 503 when persistence rejects a
write. The client only marks a set or check-in saved after acknowledgment. A
final-set write can succeed before its session-completion write fails; retrying
the same set or reopening the next-workout endpoint completes that session.
The read-only training MCP call does not perform this reconciliation write.

Completed sessions accept an exact replay of an existing set, including all
numeric values, so a lost response can be retried. A changed value or a new set
in a completed session remains rejected. Set IDs are deterministic and scoped
to the subject, session, exercise, and set number.
Deleted sessions reject retries without writes, including partial revocation
where the session is deleted but its logs and setup remain.

Load input accepts a decimal point or comma. Blank means bodyweight; explicit
zero remains zero. Invalid, nonfinite, negative, or above-500-kg input cannot be
submitted and never silently becomes bodyweight. Engine load prefills retain
the existing policy from PR 1212; acknowledged overrides restore their saved
precision.

## Regression coverage

- Training route tests cover subject isolation, restored set values, rejected
  feedback/completion writes, retry after partial persistence, exact final-set
  replay, deleted-session rejection without mutation, and advancement after
  reopening a fully logged session.
- `ChatServiceTests` covers load parsing and restoration formatting alongside
  the existing training service and carried-forward load cases.
- Three live-view UI tests cover carried-forward load and decimal override,
  acknowledged-state relaunch, failed submission and reconnect retry, and
  invalid versus blank load. The DEBUG-only `-lybUITestTrainingFixture` uses the
  production live view with a synthetic acknowledgment callback and an isolated
  `lyb.training.ui-fixture` defaults suite. It performs no auth or API calls and
  resets only its own fixture key.

The fixture's offline switch injects a transport failure. It does not prove
physical network reconnection, server deployment, TestFlight behavior, or
installed-device acceptance. Broader account-switch/health-sync recovery remains
separate acceptance work.

## Live readiness integration (LYB-129)

The default-off native Statsig gate `workout_readiness_v1` exposes a short optional
rest/readiness menu and the same reviewed voice/text controls. These controls
submit sparse observations through the existing `/feedback` command and display
its LYB-114 `nextSetRecommendation`. The client does not calculate readiness or
training prescriptions. The existing 90-second timer is retained; its expiry
says readiness is unassessed and never advances a set or removes a limitation.
LYB-114 currently returns an action, not a numeric rest prescription. “Need more
rest” and unknown input retain unknown readiness rather than inventing a breathing
or muscle limitation. Grip limitation returns the canonical adjust/skip action.

The existing workout journal now also retains the pending observation, original
wording, source, intended set, observation ID/time, and validated response.
Retry reuses that exact request, including after relaunch. A new observation
waits for the pending request to finish; logging actual sets remains available.
An exact duplicate may return an older canonical observation receipt; its
original age is retained. An acknowledged breathing/grip limitation stays visible
while later feedback is pending and when a performance-only receipt still cites
that readiness observation. A pending report never reuses an earlier proceed
decision. Wrong payload/set responses and stale journal writes
cannot acknowledge readiness. A proceed result applies only to its intended set
and expires with the existing LYB-114 observation window. Symptom-safety results
show the existing safety surface; pain/concerning voice intents use the existing
workout safety command before readiness parsing.

“That set was unusually weak” includes the actual saved reps/load/RIR and set
identity for the existing LYB-112 feedback history. Normal rep decline does not
generate this report automatically. Explicit “actually …” readiness corrections
link to the previous acknowledged observation. None of these operations writes
durable preferences, future prescriptions, or schedule revisions. Future-plan
changes must still use the separately reviewed LYB-130/37 and LYB-174 paths;
their full proposal/approval/relaunch replay is not certified by this patch.

Regression coverage extends `TrainingSessionDraftTests` for expired timers,
offline/relaunch/exact retry, single set submission, invalid context/receipts,
stale controllers, account changes, failed journal writes, duplicate receipt
age, unknown signals, correction links and symptom priority. The normal web
suite exercises the shared command parser and existing canonical feedback engine.
`testTrainingReadinessAfterTimerExpiryRetriesOfflineWithoutAdvancing` extends the
existing production-view UI fixture with an already-expired saved-set timer.
Its callbacks remain synthetic and do not certify the server or real audio.

Native XCTest execution/coverage, the UI replay, real microphone/AirPods behavior,
and the full installed-build replay against deployed services remain **unverified**
until run on the repository's native runner and a physical device at the final
commit. Keep the feature gate off and LYB-129 In Progress until those receipts
pass. The Linux implementation host has no Xcode or attached iOS device.
