create table if not exists public.body_metrics (
  id uuid primary key default gen_random_uuid(),
  user_subject text not null,
  date date not null,
  weight numeric(6, 2),
  weight_unit varchar(10) not null default 'kg',
  body_fat_percentage numeric(5, 2),
  body_fat_method varchar(20),
  muscle_mass numeric(6, 2),
  waist numeric(6, 2),
  neck numeric(6, 2),
  hip numeric(6, 2),
  notes text,
  photo_url text,
  data_source text not null default 'manual',
  source_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint body_metrics_user_date_unique unique (user_subject, date),
  constraint body_metrics_weight_unit_check check (weight_unit in ('kg', 'lbs')),
  constraint body_metrics_data_source_check check (data_source in ('manual', 'healthkit', 'smart_scale', 'bodyspec_dexa', 'caliper', 'photo'))
);

create index if not exists body_metrics_user_date_idx
  on public.body_metrics (user_subject, date desc);

create table if not exists public.schema_migrations (
  version text primary key,
  applied_at timestamptz not null default now()
);

insert into public.schema_migrations (version)
values ('20260715040000_create_body_metrics')
on conflict (version) do nothing;
