# Training save and recovery contract

The mobile `/api/auth/mobile/training/v1/next` response includes
`session.loggedSets`, an array of the authenticated subject's acknowledged sets
for that session and program. Each set contains `sessionId`, `exerciseId`,
`setNumber`, `reps`, nullable `loadKg`, and `rir`, plus server record metadata.
The iOS field is optional so responses from older servers remain decodable.
Restored sets keep their saved values and cannot be submitted again from the
live-session view. Unsaved edits are still local to the open view.

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
installed-device acceptance. Durable unsaved drafts, feedback idempotency, and
broader account-switch/health-sync recovery remain separate acceptance work.
