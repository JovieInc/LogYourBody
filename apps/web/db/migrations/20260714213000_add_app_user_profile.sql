alter table public.app_users
  add column if not exists profile_data jsonb not null default '{}'::jsonb,
  add column if not exists legal_accepted_at timestamptz,
  add column if not exists terms_version text,
  add column if not exists privacy_version text;

comment on column public.app_users.profile_data is
  'App-owned onboarding profile attributes. Identity claims remain owned by Jovie Better Auth.';
