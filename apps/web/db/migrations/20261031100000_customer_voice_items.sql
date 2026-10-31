-- Support ledger: no health data, raw messages, subjects, attachments or chat context.
create table if not exists public.customer_voice_items (
  id uuid primary key,
  channel text not null check (channel in ('email', 'chat', 'feedback', 'waitlist_reply', 'review', 'sms')),
  received_at timestamptz not null,
  sender_hash text check (sender_hash ~ '^[a-f0-9]{64}$'),
  reply_to text,
  text text not null check (length(text) between 1 and 4000),
  urgent_reasons jsonb not null default '[]'::jsonb check (jsonb_typeof(urgent_reasons) = 'array'),
  stages jsonb not null default '{}'::jsonb check (jsonb_typeof(stages) = 'object'),
  approval_receipt jsonb,
  test boolean not null default false
);
comment on table public.customer_voice_items is
  'Minimal support ledger. Text is a fixed category summary, never raw health text. reply_to is restricted plaintext pending an established field-encryption pattern. Not exposed by native sync.';
create index if not exists customer_voice_pending_idx on public.customer_voice_items (received_at)
  where not (stages ? 'forwarded');
