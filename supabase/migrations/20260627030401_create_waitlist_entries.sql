-- Waitlist entries for pre-launch email capture (LYB minimal landing)
create table if not exists public.waitlist_entries (
  id uuid default gen_random_uuid() primary key,
  email text not null,
  email_normalized text not null,
  source text not null default 'landing',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  constraint waitlist_entries_email_normalized_key unique (email_normalized)
);

create index if not exists waitlist_entries_created_at_idx
  on public.waitlist_entries (created_at desc);

alter table public.waitlist_entries enable row level security;

-- No public policies: inserts happen through the service-role API route only.