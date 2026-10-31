-- Opaque ChatGPT vault grants. Rows store token hashes and confirmed field
-- names. Measurement values and photo bytes do not belong in this table's
-- consent rows. Account deletion removes both tables before the identity row.

create table if not exists public.health_vault_grants (
  token_hash text primary key,
  user_subject text not null,
  kind text not null,
  expires_at timestamptz not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  constraint health_vault_grants_kind_check
    check (kind in ('view', 'confirm', 'consent', 'media'))
);

create index if not exists health_vault_grants_subject_idx
  on public.health_vault_grants (user_subject);

comment on table public.health_vault_grants is
  'Single-use ChatGPT vault handles. Payload is field names or a short-lived media blob, never an MCP tool result.';

create table if not exists public.health_vault_consent_log (
  id uuid primary key default gen_random_uuid(),
  user_subject text not null,
  consent_id text not null,
  fields jsonb not null,
  created_at timestamptz not null default now(),
  constraint health_vault_consent_log_fields_array
    check (jsonb_typeof(fields) = 'array')
);

create index if not exists health_vault_consent_log_subject_idx
  on public.health_vault_consent_log (user_subject, created_at);

comment on table public.health_vault_consent_log is
  'Consent events for summaries the user chose to share with ChatGPT. Fields only, not measurement values.';

insert into public.schema_migrations (version)
values ('20261030120000_health_vault_grants')
on conflict (version) do nothing;
