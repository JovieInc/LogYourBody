create table if not exists public.chat_conversations (
  id uuid primary key,
  user_subject text not null,
  title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  constraint chat_conversations_owner_unique unique (id, user_subject),
  constraint chat_conversations_title_length check (char_length(title) between 1 and 120),
  constraint chat_conversations_retention_check check (expires_at > created_at)
);

create index if not exists chat_conversations_owner_updated_idx
  on public.chat_conversations (user_subject, updated_at desc);

create index if not exists chat_conversations_expiry_idx
  on public.chat_conversations (expires_at);

create table if not exists public.chat_turns (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null,
  user_subject text not null,
  client_message_id uuid not null,
  status text not null default 'pending',
  lease_token uuid,
  lease_expires_at timestamptz,
  failure_code text,
  model text,
  input_tokens integer,
  output_tokens integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chat_turns_conversation_owner_fk
    foreign key (conversation_id, user_subject)
    references public.chat_conversations (id, user_subject)
    on delete cascade,
  constraint chat_turns_client_message_unique
    unique (conversation_id, user_subject, client_message_id),
  constraint chat_turns_status_check
    check (status in ('pending', 'completed', 'failed', 'cancelled')),
  constraint chat_turns_token_count_check
    check (
      (input_tokens is null or input_tokens >= 0) and
      (output_tokens is null or output_tokens >= 0)
    )
);

create index if not exists chat_turns_owner_created_idx
  on public.chat_turns (user_subject, created_at desc);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  turn_id uuid not null references public.chat_turns (id) on delete cascade,
  conversation_id uuid not null,
  user_subject text not null,
  role text not null,
  content text not null,
  client_message_id uuid,
  created_at timestamptz not null default now(),
  constraint chat_messages_conversation_owner_fk
    foreign key (conversation_id, user_subject)
    references public.chat_conversations (id, user_subject)
    on delete cascade,
  constraint chat_messages_turn_role_unique unique (turn_id, role),
  constraint chat_messages_role_check check (role in ('user', 'assistant')),
  constraint chat_messages_content_length check (char_length(content) between 1 and 12000),
  constraint chat_messages_user_client_id_check check (
    (role = 'user' and client_message_id is not null) or
    (role = 'assistant' and client_message_id is null)
  )
);

create index if not exists chat_messages_owner_conversation_created_idx
  on public.chat_messages (user_subject, conversation_id, created_at asc);

create table if not exists public.chat_usage_limits (
  user_subject text primary key,
  window_started_at timestamptz not null,
  window_count integer not null,
  day_started_at timestamptz not null,
  day_count integer not null,
  updated_at timestamptz not null default now(),
  constraint chat_usage_limits_counts_check check (window_count >= 0 and day_count >= 0)
);

comment on table public.chat_conversations is
  'First-party LYB chat sessions, scoped by the Jovie OAuth subject and retained for 30 days after activity.';
comment on table public.chat_messages is
  'Private user and assistant messages. Body/profile context is not copied into this table.';
comment on table public.chat_usage_limits is
  'Server-side per-subject request counters for chat abuse and cost controls, purged after 30 days of inactivity.';

insert into public.schema_migrations (version)
values ('20260802220000_create_chat_conversations')
on conflict (version) do nothing;
