# Initial training enrollment revision foundation

This slice adds server-side reviewable proposals for the **existing** two- or three-day dumbbell/full-gym baseline. It is not the full LYB-37/LYB-130 training contract: no new exercise catalogue, goals, schedule personalization, program editing, trainer authority, numerical progression policy, MCP tools, or client onboarding is introduced.

## API and authority

The authenticated `/api/auth/mobile/training/v1/program-proposals` endpoint uses the existing default-off `LYB_HYPERTROPHY_COACH_API_ENABLED` flag, bearer/cookie identity, and training rate limit. GET returns context generation and supported intent, or an owned proposal by UUID `id`; reads do not enroll or create state. POST accepts a UUID request ID, expected generation, reason, and strict `initial_enrollment` intent with explicit adult/safety confirmations and supported equipment/frequency. Unknown intent/authority/constraints fail closed. Canonical profile DOB must satisfy the existing adult check.

The server builds a versioned proposal containing self actor, explicit user-review authority, null prior revision, deterministic baseline policy/version and preview, input fingerprints/evidence, assumptions, reason and review point. A UUID-keyed PATCH explicitly applies or rejects it. Rejection has no applied setup/revision. Applying days later starts the same reviewed baseline at acceptance time; it does not advance the preview's week while waiting. Profile/input or generated policy changes require refreshed review. Request identity with a changed body conflicts; identical retries return the original stored response.

## Persistence and concurrency

The migration adds owner-scoped proposal/revision/state tables and one atomic command function. Each mutation locks the canonical `app_users` row before reading current context. Ordinary profile updates lock that same row. A decision commits revision, setup, head and receipt together, or rolls back all of them. Competing null-base proposals admit one program; apply/reject admits one terminal decision. Existing setup records retain their shape with additive revision/policy IDs; new session records retain the accepted revision ID. The existing numerical engine is unchanged.

Production legacy enrollment also captures context before body/profile/rate-limit awaits and uses the owner-locked command. An in-flight request cannot restore consent after revocation. Legacy setup classification stays with the existing `isProgramSetup` function; an old start date is still active, while invalid/outdated consent is not silently reclassified as current. Legacy enrollment remains available without a canonical head; it cannot overwrite a reviewed program's canonical head. No generic record fallback is used when the production revision port fails or lacks its captured context.

Revocation atomically advances generation, removes personal proposal/revision payloads, clears the head and tombstones the existing three training collections. Account deletion uses its existing owner predicates in one transaction, taking the owner lock first; ledger FKs cascade. Export adds owner-filtered `training_program_revisions: { proposals, revisions }` to the existing response. Export is a read of current owned data, not a cross-table point-in-time snapshot.

## Deployment and scope limits

**Apply the migration before deploying these production adapters.** Missing migration/atomic capability fails closed; there is no migration-on-request or generic upsert fallback. Missing schema can also make account export unavailable, so migration ordering is required even while the training flag remains off. No production migration, flag change, customer enrollment, provider call or new credential is part of local qualification.

Keep this foundation a draft until it composes with exact set-idempotency PR #1293 and active-prescription PR #1295 and its hosted gates pass. The existing generic internal record port remains mutable; the public generic training sync endpoint is already blocked. This slice does not claim every internal training write is protected by the new revision transaction, nor does it implement existing-program editing, delegated authority, automatic next-block policy, or complete LYB-37/LYB-130 acceptance.

## Local verification

Domain/mobile/adapter tests cover unsupported intent, canonical eligibility, proposal/readback, explicit rejection, request conflicts, no false durable success, owner-scoped export, retained baseline targets and session revision identity, plus held legacy enrollment across revoke. The PostgreSQL script uses installed binaries, a disposable Unix-socket-only cluster, actual prerequisite migrations, the candidate migration and extracted account-delete statements; it never uses `DATABASE_URL` or an external database:

```sh
python3 apps/web/db/tests/verify-training-revisions.py --postgres-bin /opt/homebrew/opt/postgresql@16/bin
```

The concurrency barriers observe real blocked PostgreSQL backends before releasing owner locks; elapsed time is not the correctness oracle. Tests include concurrent identical/different decisions, profile-edit freshness, both revoke/delete orderings, stale legacy consent, owner isolation and injected second-write/cleanup rollback. A deliberate candidate with only legacy context admission removed reproduces consent restoration after revoke; the fixed migration rejects it.
