-- Device-owned corrections never replace the imported measurement or DEXA payload.
alter table public.body_metrics
  add column if not exists is_excluded boolean not null default false,
  add column if not exists corrected_value jsonb;

alter table public.body_metrics
  add constraint body_metrics_corrected_value_object_check
  check (corrected_value is null or jsonb_typeof(corrected_value) = 'object');

comment on column public.body_metrics.is_excluded is
  'Excluded from calculations; retained in readings and sync. Never written to HealthKit.';
comment on column public.body_metrics.corrected_value is
  'Local correction overlay in kg/percent. Original weight/body_fat_percentage remain intact.';

insert into public.schema_migrations (version)
values ('20261025140000_imported_metric_overlays')
on conflict (version) do nothing;
