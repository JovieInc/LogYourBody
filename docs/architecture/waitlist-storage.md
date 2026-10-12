# Waitlist storage decision

## Decision

Use a dedicated Neon project for pre-launch marketing acquisition. Keep the
authenticated iOS product's broader data-platform decision separate.

The landing page writes through `WaitlistStoragePort` to the server-only Neon
adapter. The database connection is supplied as `WAITLIST_DATABASE_URL`; it is
never exposed to the browser. The database is isolated from Jovie's application
database and contains only waitlist email, source, lifecycle status, and
timestamps.

## Why

- Jovie already operates Neon. A separate project preserves product isolation
  while avoiding another vendor account solely for one table.
- The waitlist needs ordinary Postgres durability, uniqueness, and exportability;
  it does not need a second identity, storage, realtime, or public data API.
- The internal storage port keeps a later provider move local to one adapter.

The native product also uses the same first-party Neon data plane through
server-only APIs; its object storage and iOS sync boundaries remain explicitly
verified.

## Invitation workflow

The canonical pending-invite query is:

```sql
select id, email, source, created_at
from public.waitlist_entries
where status = 'waiting'
order by created_at;
```

After a TestFlight invitation batch is sent, record it in the same transaction:

```sql
update public.waitlist_entries
set status = 'invited', invited_at = now(), updated_at = now()
where id = any ($1::uuid[])
  and status = 'waiting';
```

Do not send email addresses to product analytics. Conversion events remain
free of contact traits; Neon is the system of record for invitation eligibility.

## Registration evidence

`accept` returns an internal `{ created: boolean }` receipt only after the
unique insert succeeds. Duplicate submissions use `ON CONFLICT DO NOTHING`:
they preserve the original source, timestamps, lifecycle and unsubscribe state.
The API never returns the receipt. New entries, duplicates and honeypots still
receive the same `202 { success: true }` response.

`web_waitlist_submitted` is a legacy browser acceptance signal. It includes
duplicates and honeypots and must not be used as the registration numerator.
Use `summarizeWaitlistRegistrations({ from, to })` from the existing server store
for the count of unique rows created in a half-open UTC interval `[from, to)`.
It reads an aggregate only: no email, identity, health value or audience export.
It includes the database observation time and explicitly marks historical
cohort provenance as `unclassified`, with `qualified_real_users: null` and no
claimed exclusions. No report endpoint, scheduled job or Summer activation is
created by this interface.

The current schema has no consent version, suppression history, test/founder
classification or delivery ledger. Existing entries must not be retroactively
granted new marketing consent. Those additions require a separate reviewed
migration and a send-disabled outbox; invitation delivery requires explicit
approval, idempotency and provider receipts. A database transaction alone
cannot establish email delivery.
