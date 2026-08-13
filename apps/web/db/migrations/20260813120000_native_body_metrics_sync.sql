-- Expand Neon body_metrics into a lossless native-sync contract without
-- collapsing same-day records. Web daily upserts keep a partial unique index
-- on origin='web'; native rows are identified by the client UUID primary key.
-- Neon replaces Postgres only. Object storage and compute stay elsewhere.

alter table public.body_metrics
  add column if not exists measured_at timestamptz,
  add column if not exists local_date date,
  add column if not exists bone_mass numeric(10, 2),
  add column if not exists waist_unit varchar(10) not null default 'cm',
  add column if not exists origin text not null default 'web',
  add column if not exists deleted_at timestamptz,
  add column if not exists client_created_at timestamptz,
  add column if not exists client_updated_at timestamptz;

update public.body_metrics
set
  measured_at = coalesce(measured_at, (date::timestamp at time zone 'UTC')),
  local_date = coalesce(local_date, date),
  client_created_at = coalesce(client_created_at, created_at),
  client_updated_at = coalesce(client_updated_at, updated_at)
where
  measured_at is null
  or local_date is null
  or client_created_at is null
  or client_updated_at is null;

alter table public.body_metrics
  alter column measured_at set not null,
  alter column local_date set not null,
  alter column client_created_at set not null,
  alter column client_updated_at set not null;

alter table public.body_metrics
  drop constraint if exists body_metrics_origin_check,
  drop constraint if exists body_metrics_waist_unit_check;

alter table public.body_metrics
  add constraint body_metrics_origin_check check (origin in ('web', 'native')),
  add constraint body_metrics_waist_unit_check check (waist_unit in ('cm', 'in'));

create unique index if not exists body_metrics_web_subject_date_unique
  on public.body_metrics (user_subject, date)
  where origin = 'web' and deleted_at is null;

alter table public.body_metrics
  drop constraint if exists body_metrics_user_date_unique;

create index if not exists body_metrics_owner_updated_idx
  on public.body_metrics (user_subject, updated_at asc, id asc);

create index if not exists body_metrics_owner_local_date_idx
  on public.body_metrics (user_subject, local_date desc, measured_at desc);

comment on column public.body_metrics.measured_at is
  'Native record instant. Web rows use UTC midnight of date.';
comment on column public.body_metrics.local_date is
  'Client calendar date. Independent of measured_at timezone conversion.';
comment on column public.body_metrics.bone_mass is
  'Bone mass in kilograms. Native-required; never silently dropped.';
comment on column public.body_metrics.origin is
  'web rows remain one-per-day; native rows keep client UUID identity.';
comment on column public.body_metrics.deleted_at is
  'Tombstone for idempotent native delete/pull. Null means live.';
comment on column public.body_metrics.client_created_at is
  'Original client created_at. Server created_at remains the insert clock.';
comment on column public.body_metrics.client_updated_at is
  'Original client updated_at. Server updated_at is the pull cursor.';

insert into public.schema_migrations (version)
values ('20260813120000_native_body_metrics_sync')
on conflict (version) do nothing;
