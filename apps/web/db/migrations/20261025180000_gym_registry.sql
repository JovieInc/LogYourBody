-- User-confirmed inventory only. No location data, presets, or backfill.
create table public.gyms (
  id uuid primary key,
  owner_id uuid not null references public.app_users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  coarse_region text check (coarse_region is null or char_length(btrim(coarse_region)) between 1 and 120),
  equipment text[] not null check (
    equipment <@ array['dumbbells','barbell','ez_bar','machine','cable','bench','adjustable_bench','bodyweight','smith']::text[]
    and array_position(equipment, null) is null
  ),
  preferred_machines text[] not null check (cardinality(preferred_machines) <= 30),
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);
create index gyms_owner_idx on public.gyms(owner_id);

alter table public.gyms enable row level security;
alter table public.gyms force row level security;
-- The first-party adapter sets this transaction-local value from verified
-- account admission, never from a client-supplied owner or a pooled session.
create policy gyms_owner on public.gyms for all
  using (owner_id::text = nullif(current_setting('lyb.gym_owner_id', true), ''))
  with check (owner_id::text = nullif(current_setting('lyb.gym_owner_id', true), ''));

insert into public.schema_migrations(version) values ('20261025180000_gym_registry')
  on conflict do nothing;
