-- Dedicated marketing-acquisition store. This database is not exposed to a
-- browser-side data API; the server-only waitlist adapter is its sole writer.
create table if not exists public.waitlist_entries (
  id uuid primary key default gen_random_uuid(),
  email text not null check (char_length(email) between 3 and 254),
  email_normalized text not null check (char_length(email_normalized) between 3 and 254),
  source varchar(64) not null default 'landing',
  status varchar(24) not null default 'waiting'
    check (status in ('waiting', 'invited', 'joined', 'unsubscribed')),
  invited_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint waitlist_entries_email_normalized_key unique (email_normalized)
);

create index if not exists waitlist_entries_created_at_idx
  on public.waitlist_entries (created_at desc);

create index if not exists waitlist_entries_status_created_at_idx
  on public.waitlist_entries (status, created_at desc);

create table if not exists public.schema_migrations (
  version text primary key,
  applied_at timestamp with time zone not null default now()
);

insert into public.schema_migrations (version)
values ('20260715032000_create_waitlist_entries')
on conflict (version) do nothing;
