-- Additive only; existing accounts and stores have no dated outcome until saved.
alter table public.app_users
  add column if not exists dated_outcome jsonb,
  add column if not exists dated_outcome_revision uuid;

-- Durable recompute requests, not training prescriptions. Account deletion cascades.
create table if not exists public.dated_outcome_recompute_requests (
  owner_id uuid not null references public.app_users(id) on delete cascade,
  request_id uuid not null,
  edit jsonb not null,
  plan_inputs jsonb not null,
  created_at timestamptz not null default now(),
  primary key (owner_id, request_id)
);
alter table public.dated_outcome_recompute_requests enable row level security;
revoke all on public.dated_outcome_recompute_requests from public;

create or replace function public.lyb_save_dated_outcome(p_owner uuid, p_edit jsonb, p_inputs jsonb)
returns jsonb language plpgsql as $$
declare
  v_user public.app_users%rowtype;
  v_prior jsonb;
  v_request uuid := (p_edit->>'requestId')::uuid;
  v_inputs jsonb;
  v_old_keys text[];
begin
  -- Same owner row lock as account admission/deletion and LYB-130 revisions.
  select * into v_user from public.app_users where id=p_owner for update;
  if not found then raise exception 'account_changed' using errcode='LYB01'; end if;

  select edit into v_prior from public.dated_outcome_recompute_requests
    where owner_id=p_owner and request_id=v_request;
  if found then
    if v_prior is distinct from p_edit then return jsonb_build_object('kind','request_conflict'); end if;
    -- A replay acknowledges its own revision even when a later edit has arrived.
    return jsonb_build_object('kind','saved','snapshot',jsonb_build_object('revision',v_request,'value',p_edit->'value'));
  end if;
  if v_user.dated_outcome_revision is distinct from (p_edit->>'previousRevision')::uuid then
    return jsonb_build_object('kind','revision_conflict');
  end if;
  -- Feed the existing LYB-130 input source without applying/revising a program.
  -- Clearing an outcome-owned availability field must not retain its old value.
  select coalesce(array_agg(key),'{}'::text[]) into v_old_keys
    from jsonb_object_keys(coalesce(v_user.dated_outcome->'constraints'->'availability','{}'::jsonb)) as key;
  v_inputs := (coalesce(v_user.profile_data->'training_inputs','{}'::jsonb) - v_old_keys) || p_inputs;
  update public.app_users set dated_outcome=p_edit->'value', dated_outcome_revision=v_request,
    profile_data=profile_data || jsonb_build_object('training_inputs',v_inputs,'dated_outcome_revision',v_request),
    updated_at=now()
    where id=p_owner;
  insert into public.dated_outcome_recompute_requests(owner_id,request_id,edit,plan_inputs)
    values(p_owner,v_request,p_edit,p_inputs);
  return jsonb_build_object('kind','saved','snapshot',jsonb_build_object('revision',v_request,'value',p_edit->'value'));
end;
$$;
revoke all on function public.lyb_save_dated_outcome(uuid,jsonb,jsonb) from public;

insert into public.schema_migrations(version) values ('20261025130000_dated_outcome') on conflict do nothing;
