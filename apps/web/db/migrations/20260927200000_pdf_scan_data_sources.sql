alter table public.body_metrics
  drop constraint if exists body_metrics_data_source_check;

alter table public.body_metrics
  add constraint body_metrics_data_source_check check (
    data_source in (
      'manual',
      'healthkit',
      'smart_scale',
      'bodyspec_dexa',
      'dexa_pdf',
      'inbody_pdf',
      'caliper',
      'photo'
    )
  );

insert into public.schema_migrations (version)
values ('20260927200000_pdf_scan_data_sources')
on conflict (version) do nothing;
