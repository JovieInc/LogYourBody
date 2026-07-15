# Database Credential Exposure Audit — 2026-07-14

## Finding

A plaintext database password appeared in two tracked setup documents:

- `apps/web/CLAUDE.md`
- `apps/web/PROFILE_SETTINGS_IMPLEMENTATION.md`

The value was introduced in commit `d79327a5f` on 2025-07-04 and therefore remains recoverable from Git history. This audit intentionally does not reproduce it.

## Remediation

- Removed the plaintext value from both active documents.
- Replaced password-bearing command examples with the approved secret-manager/environment-variable workflow.
- Searched the active worktree for the exposed value; no remaining occurrence was found.
- Tested the historical value against the linked Supabase project's direct Postgres endpoint; it did not authenticate, confirming it is no longer the active database password.

No password change was issued because the exposed value was already inactive. If a future provider audit identifies another active copy, rotate it through the Supabase dashboard or Management API and update every legitimate consumer before resuming deployments.

## Follow-up Guardrail

Database passwords must never appear in shell history examples, tracked documentation, source code, issue text, or pull-request descriptions. Supply them only through the approved secret manager or process environment.
