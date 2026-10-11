-- Immutable, authenticated provider events. Not part of customer record sync.
create table if not exists public.revenuecat_events (
  app_id text not null,
  event_id text not null,
  fingerprint text not null check (fingerprint ~ '^[a-f0-9]{64}$'),
  payload jsonb not null,
  verification_mode text not null default 'hmac_sha256' check (verification_mode = 'hmac_sha256'),
  received_at timestamptz not null default now(),
  primary key (app_id, event_id),
  check (jsonb_typeof(payload -> 'event') is not distinct from 'object'),
  check ((payload -> 'event' ->> 'app_id') is not distinct from app_id),
  check ((payload -> 'event' ->> 'id') is not distinct from event_id)
);

comment on table public.revenuecat_events is
  'RevenueCat delivery ledger. Runtime inserts only; duplicate event IDs never replace payloads. Sandbox and unsupported events are retained.';
