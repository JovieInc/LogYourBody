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

- The historical LogYourBody Supabase production and development hosts no
  longer resolve, so they cannot safely receive launch signups.
- Jovie already operates Neon. A separate project preserves product isolation
  while avoiding another vendor account solely for one table.
- The waitlist needs ordinary Postgres durability, uniqueness, and exportability;
  it does not need Supabase Auth, Storage, Realtime, Functions, or a public Data
  API.
- The internal storage port keeps a later provider move local to one adapter.

This is not a decision to migrate the native product to Neon. That migration
would also need explicit replacements and verified cutovers for object storage,
Realtime, Edge Functions, RLS/Data API behavior, and iOS sync. It should be
evaluated as its own data-migration project before activated users depend on it.

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
anonymous; Neon is the system of record for invitation eligibility.
