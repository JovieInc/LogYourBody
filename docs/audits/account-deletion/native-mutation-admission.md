# Native account mutation admission

Public native body-metric and generic-record mutations capture the current product account's physical UUID after authentication and before reading the request body. The explicit `accountMutations` port carries that same admission through push, tombstone and medication-completion operations. Missing capabilities fail closed; public routes never fall back to subject-only storage methods. Canonical training collections still require the training API and its stronger consent/revision admission.

The first statement in each bounded mutation transaction calls `lyb_native_account_admit`. It locks the canonical `app_users` row and compares its UUID with the capture using a NULL-safe comparison. All request writes follow under that lock. Account deletion uses the same guard and transaction, retaining all existing cleanup predicates. Thus a writer admitted first finishes before deletion removes its rows; a deleted or replaced account rejects an older captured mutation. A later statement failure rolls back the whole batch.

Mobile and web account deletion capture before their cleanup awaits and pass that capture to SQL. Already absent accounts return the existing successful response without new cleanup; an account that changes after capture rejects deletion. The mobile external photo cleanup remains outside the database transaction.

Expected mutation failures are `404 account_not_found`, `409 account_changed`, and `503 account_admission_unavailable` (including a missing admission migration). They never return a successful record acknowledgement. Success schemas, record IDs, same-owner upserts, tombstones, foreign-ID rejection and opaque DEXA payload preservation stay unchanged. Existing subject-only storage methods remain internal compatibility seams; this change's guarantee applies to the public native mutation handlers, not every product writer.

Apply `20261010120000_native_account_admission.sql` before this server version. Old server instances must drain before claiming the public native write fence is in effect. No runtime flag bypasses this privacy check. The existing deploy workflow applies migrations before deploying the server.

## Boundaries

The issuer bearer token and mobile product-session response contain no product-account UUID or incarnation binding. A request whose authentication has not completed until after same-subject account recreation can capture the new owner; this repair does not revoke issuer tokens or establish historical token ownership. Supporting that stronger claim requires a separately reviewed product-session/issuer contract.

Existing R2 photo keys use a subject prefix, and presigned uploads can outlive deletion. The SQL fence cannot serialize external object cleanup or prevent a late authorized upload. Account-scoped R2 keys/cleanup and late-upload erasure require separate qualification. This is not a claim of complete cross-provider account erasure.

## Local evidence

The unchanged route writers reproduce five successful stale native mutations and one replacement-account deletion across deterministic held awaits. Actual original adapter SQL reproduces native-record and body-metric row resurrection after deletion in a disposable PostgreSQL cluster. Fixed tests cover captured route ownership, absent/capability errors, the acknowledged bearer-delay boundary, actual two-connection lock waits in both orders, replacement UUIDs, batch and deletion rollback, foreign rows and opaque payloads.

Run the opt-in local database harness with installed PostgreSQL binaries:

```sh
python3 apps/web/db/tests/verify-native-account-admission.py --postgres-bin /path/to/postgresql/bin
```

It creates only synthetic rows in a disposable socket-only cluster, never reads `DATABASE_URL`, and never calls an external provider.
