-- Anonymous abuse counters live in the product database, whose migration runner
-- runs before deployment. Waitlist emails remain in WAITLIST_DATABASE_URL.
create table if not exists public.waitlist_rate_limits (
  client_key text primary key check (client_key ~ '^[a-f0-9]{64}$'),
  attempts integer not null check (attempts > 0),
  expires_at timestamp with time zone not null
);

create index if not exists waitlist_rate_limits_expires_at_idx
  on public.waitlist_rate_limits (expires_at);

insert into public.schema_migrations(version)
values ('20261023150000_waitlist_rate_limits')
on conflict do nothing;
