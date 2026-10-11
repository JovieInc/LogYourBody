-- Accept PDF imports whose measurement method is unidentified without
-- relabeling existing rows. Deploy this constraint and the accepting API
-- before a native writer starts sending the explicit pdf_import source.
alter table public.body_metrics
  drop constraint if exists body_metrics_data_source_check,
  add constraint body_metrics_data_source_check check (
    data_source in (
      'manual',
      'healthkit',
      'smart_scale',
      'bodyspec_dexa',
      'dexa_pdf',
      'inbody_pdf',
      'pdf_import',
      'caliper',
      'photo'
    )
  );

insert into public.schema_migrations (version)
values ('20261009210845_unidentified_pdf_import_source')
on conflict (version) do nothing;
