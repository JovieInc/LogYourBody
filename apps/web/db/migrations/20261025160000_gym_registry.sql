-- Explicitly registered gyms only: no location, inferred inventory, or default gym.
create table public.gyms (
  id uuid primary key,
  owner_id uuid not null references public.app_users(id) on delete cascade,
  user_subject text not null,
  payload jsonb not null,
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint gyms_payload_check check (
    payload ?& array['name', 'equipment', 'preferredMachines']
    and jsonb_typeof(payload) = 'object'
    and jsonb_typeof(payload->'name') = 'string'
    and length(btrim(payload->>'name')) between 1 and 100
    and jsonb_typeof(payload->'equipment') = 'array'
    and jsonb_typeof(payload->'preferredMachines') = 'array'
  )
);
create index gyms_owner_idx on public.gyms(user_subject, id);

alter table public.gyms enable row level security;
alter table public.gyms force row level security;
create policy gyms_owner on public.gyms
  using (user_subject = nullif(current_setting('app.user_subject', true), ''))
  with check (user_subject = nullif(current_setting('app.user_subject', true), ''));

insert into public.schema_migrations(version)
values ('20261025160000_gym_registry') on conflict (version) do nothing;
