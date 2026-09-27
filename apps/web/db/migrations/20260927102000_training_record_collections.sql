alter table public.native_records
  drop constraint if exists native_records_collection_check;

alter table public.native_records
  add constraint native_records_collection_check check (
    collection in (
      'daily_metrics',
      'glp1_medications',
      'glp1_dose_logs',
      'dexa_results',
      'progress_photos',
      'training_sessions',
      'logged_sets',
      'training_feedback'
    )
  );

insert into public.schema_migrations (version)
values ('20260927102000_training_record_collections')
on conflict (version) do nothing;
