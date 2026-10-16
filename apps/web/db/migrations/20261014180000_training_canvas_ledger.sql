-- Compare-and-swap storage for the mesocycle canvas ledger.
-- The revision rules live in the application service. This function only
-- fences the admitted owner incarnation and refuses a moved write token.
create table if not exists public.training_canvas_ledgers (
  identity_provider text not null default 'jovie' check (identity_provider = 'jovie'),
  user_subject text primary key,
  write bigint not null check (write >= 0),
  generation bigint not null check (generation >= 0),
  payload jsonb not null,
  updated_at timestamptz not null,
  foreign key (identity_provider, user_subject)
    references public.app_users(identity_provider, identity_subject) on delete cascade,
  check ((payload->>'version') = '1'),
  check ((payload->>'write')::bigint = write),
  check ((payload->>'generation')::bigint = generation)
);

create or replace function public.training_canvas_load(p_subject text)
returns jsonb language sql stable as $$
  select payload from public.training_canvas_ledgers where user_subject = p_subject;
$$;

-- Do not retain the unadmitted overload if this preview migration is reapplied.
drop function if exists public.training_canvas_save(text, bigint, jsonb);
create or replace function public.training_canvas_save(
  p_subject text, p_owner uuid, p_expected bigint, p_payload jsonb
) returns jsonb language plpgsql as $$
declare
  v_write bigint;
  v_next bigint;
begin
  perform public.lyb_native_account_admit(p_subject, p_owner);
  if p_payload->>'version' is distinct from '1'
     or p_payload->>'write' is null
     or p_payload->>'generation' is null then
    return jsonb_build_object('kind', 'invalid');
  end if;
  v_next := (p_payload->>'write')::bigint;
  select write into v_write from public.training_canvas_ledgers
    where user_subject = p_subject for update;
  if p_expected is null then
    if found then return jsonb_build_object('kind', 'stale'); end if;
    insert into public.training_canvas_ledgers(user_subject, write, generation, payload, updated_at)
      values(p_subject, v_next, (p_payload->>'generation')::bigint, p_payload, now());
    return jsonb_build_object('kind', 'saved');
  end if;
  if not found or v_write is distinct from p_expected or v_next < p_expected then
    return jsonb_build_object('kind', 'stale');
  end if;
  update public.training_canvas_ledgers
    set write = v_next,
        generation = (p_payload->>'generation')::bigint,
        payload = p_payload,
        updated_at = now()
    where user_subject = p_subject and write = p_expected;
  if not found then return jsonb_build_object('kind', 'stale'); end if;
  return jsonb_build_object('kind', 'saved');
end;
$$;

insert into public.schema_migrations(version) values('20261014180000_training_canvas_ledger')
  on conflict(version) do nothing;
