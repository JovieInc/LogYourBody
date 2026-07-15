create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  identity_provider text not null default 'jovie',
  identity_subject text not null,
  phone_e164 text,
  email text,
  display_name text,
  avatar_url text,
  onboarding_completed_at timestamptz,
  last_signed_in_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_users_identity_provider_check check (identity_provider = 'jovie'),
  constraint app_users_identity_unique unique (identity_provider, identity_subject)
);

create index if not exists app_users_phone_e164_idx
  on public.app_users (phone_e164)
  where phone_e164 is not null;

comment on table public.app_users is
  'LYB product principals projected from the shared Jovie Better Auth identity authority.';
comment on column public.app_users.identity_subject is
  'Immutable OpenID Connect sub issued by https://jov.ie/api/auth.';
