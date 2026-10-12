-- Hard-cut native product records for daily metrics, GLP-1, DEXA, and
-- progress-photo metadata. Payload is stored as jsonb so native fields are
-- not truncated. Retired provider rows are not backfilled.

create table if not exists public.native_records (
  collection text not null,
  id uuid not null,
  user_subject text not null,
  payload jsonb not null,
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (collection, id),
  constraint native_records_collection_check check (
    collection in (
      'daily_metrics',
      'glp1_medications',
      'glp1_dose_logs',
      'dexa_results',
      'progress_photos'
    )
  )
);

create index if not exists native_records_owner_updated_idx
  on public.native_records (user_subject, collection, updated_at asc, id asc);

comment on table public.native_records is
  'Subject-scoped native sync documents after the first-party data cutover. No backfill.';

insert into public.schema_migrations (version)
values ('20260813130000_native_product_records')
on conflict (version) do nothing;
