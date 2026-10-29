# Dated outcome storage (LYB-268)

`DatedOutcome` persists the user's selected metric/value, calendar date, and
constraints. It does not prescribe a target or execute the training engine.
The contract remains in Jovie main:
[launch contract](https://github.com/JovieInc/Jovie/blob/main/docs/product/lyb-launch-contract.md)
and [JSON fixture](https://github.com/JovieInc/Jovie/blob/main/scripts/fixtures/lyb-launch-contract.json).
Implementation consumed `promise.requiredInputs` (`outcome`, `outcomeDate`,
`constraints`), `launch.deadline`, and `launch.deadline-replan` from the fixture
with Git blob `e241610a21b7e103187491072d3a4119ed85048e`. No upstream policy is
vendored here.

The entry point for the parent journey is
`RealtimeSyncManager.shared.datedOutcomeStore`. The parent supplies one complete
value to `save`, including all fields changed in the same Save action. There is
no new screen in this storage slice. Native writes/sync require the default-off
Platform/Statsig gate `dated_outcome_v1`; API traffic requires
`LYB_DATED_OUTCOME_ENABLED=true`. Enable both only after migration and native
validation.

The additive V6 Core Data model adds `CachedDatedOutcome` while preserving V1–V5 byte-for-byte. Main’s V5 contains `CachedWorkoutReconciliationDay`; the earlier dated-outcome V5 proposal must not replace that published schema. Both app and widget select V6.
An owner-scoped journal commits each value and recompute request together.
Unchanged values create no request. The current value and pending requests
survive store reopening and logout; signed-out reads/writes fail closed, and
account switches query only their own rows. Account deletion clears the journal.
Successful acknowledgement removes only old acknowledged history. Failed/offline
requests remain pending with their original UUID. Pending counts include them.

`PUT /api/auth/mobile/dated-outcome` sends the full value, `requestId`, and
`previousRevision` (explicit null on first save). The first-party API captures the
product account incarnation and admits the write under the existing account lock.
The additive Neon migration stores the outcome on `app_users` and creates a
durable `dated_outcome_recompute_requests` row in the same transaction. Concurrent
retries with the same UUID/body acknowledge the original save; reusing a UUID
with another body or writing from a stale revision returns 409. Native retains
the unsynced edit on conflict for explicit reconciliation; it never overwrites a
newer cloud value automatically. A receipt after a session change cannot clear
pending work. GET and account export are owner-scoped and uncached; deletion
cascades through request history.

The request's `plan_inputs` uses LYB-130's existing partial `PlanningInputs`
schema. Saving also updates `profile_data.training_inputs`, its existing canonical
input source, and changes the profile fingerprint to invalidate stale proposals.
Other known training inputs remain intact; removing an outcome-owned availability
field removes its previous override. Travel and maintenance intervals stay
explicit in the request value, without inventing training quantities. No program,
session, accepted revision, consent, or training authority changes. Consuming the
request to deliver a new action remains with the parent journey.

Supabase is retired in this repository. This slice uses the canonical Neon
migration directory and `pnpm db:schema:check` instead of adding Supabase drift.

Verification:

- `DatedOutcomeStoreTests` covers SQLite reopen, account isolation, exact request
  counts, failure rollback, retry identity, stale receipts, clean-device pull,
  and V4/V5-to-V6 migration retaining measurements, profile targets and existing workout-reconciliation payloads.
  It is wired into the existing native test target and is not skipped by Unit.
- The existing disposable PostgreSQL verifier now runs
  `apps/web/db/tests/verify-dated-outcomes.ts`, exercising the real adapter,
  migration/replay over existing accounts, concurrent duplicates/conflicts,
  LYB-130 inputs, atomic rollback, export isolation, and deletion/recreation.
- The API/schema/adapter Jest tests run through the existing web test script.
- For upstream fixture reconciliation, supply `LYB_LAUNCH_CONTRACT_PATH` pointing
  to the JSON read from Jovie main. The native tests and PostgreSQL verifier read
  that external file and compare its required inputs to the encoded value.
  Without that input, offline CI still exercises the wire/storage behavior; it
  does not claim current upstream policy reconciliation.

On the implementation Linux host, PostgreSQL16 and web checks can execute;
XCTest/Core Data runtime execution and native coverage require the repository's
real macOS runner. TestFlight evidence remains with LYB-183.

The existing required native-project guard freezes each reviewed model version, verifies app/widget membership and current-version selection, and rejects a reused version before native build. Its model files and current-version plist participate in the existing Turbo test inputs. Native SQLite migration tests remain required; static fingerprint checks alone do not prove runtime migration.
