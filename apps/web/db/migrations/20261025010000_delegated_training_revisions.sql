-- Extend the existing owner-locked revision transaction; no alternate plan store.
-- Fingerprint all training evidence, including corrections, tombstones and feedback.
alter table public.training_revision_proposals add column if not exists decision_attempts jsonb not null default '[]'::jsonb;

create or replace function public.training_stored_proposal(p_id uuid, p_subject text)
returns jsonb language sql stable as $$
  select jsonb_build_object('proposal',payload,'status',status,'requestHash',request_hash,'receipt',receipt)
    || case when jsonb_array_length(decision_attempts)>0 then jsonb_build_object('attempts',decision_attempts) else '{}'::jsonb end
  from public.training_revision_proposals where id=p_id and user_subject=p_subject;
$$;

create or replace function public.training_planning_fingerprint(p_subject text)
returns text language sql stable as $$
  select md5(coalesce(jsonb_agg(jsonb_build_object('collection',collection,'id',id,
    'payload',payload,'deletedAt',deleted_at,'updatedAt',updated_at) order by collection,id)::text,'[]'))
  from public.native_records where user_subject=p_subject
    and collection in ('training_sessions','logged_sets','training_feedback');
$$;

create or replace function public.training_revision_command(p_subject text, p_action text, p_request jsonb)
returns jsonb language plpgsql as $$
declare
  v_owner uuid;
  v_context jsonb;
  v_proposal public.training_revision_proposals%rowtype;
  v_generation bigint;
  v_head uuid;
  v_setup jsonb;
  v_receipt jsonb;
  v_id uuid;
  v_other uuid;
  v_count integer;
  v_now timestamptz;
  v_delegated boolean := false;
  v_current jsonb;
  v_actor jsonb;
begin
  select id into v_owner from public.app_users
    where identity_provider='jovie' and identity_subject=p_subject for update;
  if not found then return jsonb_build_object('kind','owner_missing'); end if;
  v_context := public.training_revision_context(p_subject);
  v_generation := (v_context->>'generation')::bigint;
  v_head := (v_context->>'headRevision')::uuid;
  select payload into v_current from public.native_records where user_subject=p_subject
    and collection='training_feedback' and deleted_at is null
    and payload->>'programRevisionId'=v_head::text and payload->>'record_type'='program_setup';

  if p_action='revoke' then
    insert into public.training_revision_state(user_subject,generation) values(p_subject,v_generation+1)
      on conflict(user_subject) do update set generation=excluded.generation,head_revision=null;
    delete from public.training_revision_proposals where user_subject=p_subject;
    update public.native_records set deleted_at=now(),updated_at=now()
      where user_subject=p_subject and collection in ('training_sessions','logged_sets','training_feedback')
        and deleted_at is null;
    get diagnostics v_count = row_count;
    return jsonb_build_object('kind','revoked','deletedRecords',v_count);
  end if;

  if p_action='legacy_enroll' then
    if p_request->'context' is distinct from
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision') then
      return jsonb_build_object('kind','stale_context');
    end if;
    if v_head is not null then return jsonb_build_object('kind','program_already_enrolled'); end if;
    v_setup := p_request->'setup';
    insert into public.native_records(collection,id,user_subject,payload,deleted_at,updated_at)
      values('training_feedback',(v_setup->>'id')::uuid,p_subject,v_setup || '{"record_type":"program_setup"}'::jsonb,null,now())
      on conflict(collection,id) do update set payload=excluded.payload,deleted_at=null,updated_at=now()
        where public.native_records.user_subject=excluded.user_subject returning id into v_id;
    if not found then return jsonb_build_object('kind','request_conflict'); end if;
    insert into public.training_revision_state(user_subject,generation) values(p_subject,v_generation+1)
      on conflict(user_subject) do update set generation=excluded.generation;
    return jsonb_build_object('kind','enrolled');
  end if;

  if p_action='create' then
    select * into v_proposal from public.training_revision_proposals
      where user_subject=p_subject and request_id=(p_request->>'requestId')::uuid;
    if found then
      if v_proposal.request_hash<>p_request->>'requestHash' then
        return jsonb_build_object('kind','request_conflict');
      end if;
      return jsonb_build_object('kind','stored','stored',public.training_stored_proposal(v_proposal.id,p_subject));
    end if;
    v_delegated := coalesce(p_request->'proposal'->>'version'='2',false);
    if v_head is not null and not v_delegated then return jsonb_build_object('kind','program_already_enrolled'); end if;
    if v_delegated then
      if p_request->'proposal'->'baseRevision' is distinct from v_context->'headRevision' then
        return jsonb_build_object('kind','revision_conflict');
      end if;
      if p_request->'proposal'->>'ownerSubject' is distinct from p_subject
        or p_request->'proposal'->'inputEvidence'->>'fingerprint' is distinct from public.training_planning_fingerprint(p_subject) then
        return jsonb_build_object('kind','stale_context');
      end if;
      if v_head is null and exists(select 1 from public.native_records where user_subject=p_subject and collection='training_feedback' and deleted_at is null and payload->>'record_type'='program_setup'
        and payload->>'consentVersion'='hypertrophy-coach-v1' and payload->>'adultConfirmed'='true' and payload->>'safetyConfirmed'='true')
        and not exists(select 1 from public.native_records where user_subject=p_subject and collection='training_feedback' and deleted_at is null
          and payload->>'record_type'='program_setup' and id::text=p_request->'proposal'->'priorState'->>'id') then
        return jsonb_build_object('kind','program_already_enrolled');
      end if;
    end if;
    if (p_request->'proposal'->'context') is distinct from
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision') then
      return jsonb_build_object('kind','stale_context');
    end if;
    if not v_delegated and p_request->'proposal'->'actor'->>'subject' is distinct from p_subject then
      return jsonb_build_object('kind','request_conflict');
    end if;
    insert into public.training_revision_state(user_subject) values(p_subject) on conflict do nothing;
    insert into public.training_revision_proposals(id,user_subject,request_id,request_hash,generation,payload,created_at)
      values((p_request->'proposal'->>'id')::uuid,p_subject,(p_request->>'requestId')::uuid,
        p_request->>'requestHash',v_generation,p_request->'proposal',(p_request->'proposal'->>'createdAt')::timestamptz);
    return jsonb_build_object('kind','stored','stored',public.training_stored_proposal((p_request->'proposal'->>'id')::uuid,p_subject));
  end if;

  if p_action not in ('apply','reject') then raise exception 'unsupported_training_revision_command'; end if;
  select id into v_other from public.training_revision_proposals
    where user_subject=p_subject and (decision_id=(p_request->>'requestId')::uuid
      or decision_attempts @> jsonb_build_array(jsonb_build_object('requestId',p_request->>'requestId')));
  if found and v_other<>(p_request->>'proposalId')::uuid then
    return jsonb_build_object('kind','request_conflict');
  end if;
  select * into v_proposal from public.training_revision_proposals
    where id=(p_request->>'proposalId')::uuid and user_subject=p_subject for update;
  if not found then return jsonb_build_object('kind','proposal_not_found'); end if;
  -- A held decision cannot target a recreated owner's identical deterministic ID.
  v_delegated := coalesce(v_proposal.payload->>'version'='2',false);
  if p_request->'context'->>'ownerId' is distinct from v_owner::text
     or (p_request->'context'->'generation' is distinct from v_context->'generation'
       and not coalesce((v_delegated and v_proposal.decision_id=(p_request->>'requestId')::uuid
         and p_request->'context'->>'generation'=v_proposal.generation::text),false)) then
    return jsonb_build_object('kind','stale_context');
  end if;
  if v_proposal.decision_id=(p_request->>'requestId')::uuid then
    if v_proposal.decision_hash<>p_request->>'requestHash' then
      return jsonb_build_object('kind','request_conflict');
    end if;
    return jsonb_build_object('kind','decided','receipt',v_proposal.receipt);
  end if;
  if v_delegated then
    v_actor := p_request->'actor';
    if not coalesce(
      (v_actor->>'kind'='user' and v_actor->>'subject'=p_subject)
      or (v_actor->>'kind'='trainer' and v_actor->>'subject'=v_current->'delegated'->'authority'->>'trainerSubject')
      or (v_actor->>'kind'='coach' and v_actor->>'subject'='lyb-coach' and v_current->'delegated'->'authority'->>'coachDelegated'='true' and v_proposal.payload->>'authority'='coach_delegation'), false) then
      return jsonb_build_object('kind','unauthorized_actor');
    end if;
    if exists(select 1 from jsonb_array_elements(v_proposal.decision_attempts) attempt
      where attempt->>'requestId'=p_request->>'requestId' and attempt->>'requestHash' is distinct from p_request->>'requestHash') then
      return jsonb_build_object('kind','request_conflict');
    end if;
  end if;
  if v_proposal.status<>'proposed' then return jsonb_build_object('kind','already_decided'); end if;
  -- Legacy proposals remain readable/exportable but cannot authorize new writes.
  if v_proposal.payload->'context'->>'ownerId' is distinct from v_owner::text then
    return jsonb_build_object('kind','stale_context');
  end if;
  if v_generation<>v_proposal.generation then return jsonb_build_object('kind','stale_context'); end if;
  v_now := (p_request->>'now')::timestamptz;
  if p_action='apply' then
    if v_delegated then
      if v_proposal.payload->'baseRevision' is distinct from v_context->'headRevision' then
        return jsonb_build_object('kind','revision_conflict');
      end if;
      if v_proposal.payload->'inputEvidence'->>'fingerprint' is distinct from public.training_planning_fingerprint(p_subject) then
        return jsonb_build_object('kind','stale_context');
      end if;
      if exists(select 1 from public.native_records where user_subject=p_subject and collection='training_sessions' and deleted_at is null and payload->>'status' in ('in_progress','paused') and payload->>'programSetupId'=v_proposal.payload->>'programId') then
        if not exists(select 1 from jsonb_array_elements(v_proposal.decision_attempts) attempt where attempt->>'requestId'=p_request->>'requestId') then
          update public.training_revision_proposals set decision_attempts=decision_attempts || jsonb_build_array(jsonb_build_object(
            'requestId',p_request->>'requestId','requestHash',p_request->>'requestHash','actor',v_actor,
            'status','delayed','reason','active_workout','attemptedAt',v_now,'reviewPoint','after_current_workout')) where id=v_proposal.id;
        end if;
        return jsonb_build_object('kind','delayed_active_workout');
      end if;
    elsif v_head is not null then return jsonb_build_object('kind','revision_conflict'); end if;
    if v_proposal.payload->'context' is distinct from
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision') then
      return jsonb_build_object('kind','stale_context');
    end if;
    v_id := (p_request->>'revisionId')::uuid;
    v_setup := p_request->'setup';
    if v_setup->>'id' is distinct from v_proposal.payload->>'programId'
       or v_setup->>'programRevisionId' is distinct from v_id::text then
      return jsonb_build_object('kind','request_conflict');
    end if;
    if v_delegated and (v_setup->'delegated' is distinct from v_proposal.payload->'proposedState'
       or v_setup->>'programPolicyVersion' is distinct from v_proposal.payload->>'policyVersion'
       or v_setup->>'sessionsPerWeek' is distinct from v_setup->'delegated'->'inputs'->>'sessionsPerWeek'
       or v_setup->>'equipment' is distinct from v_setup->'delegated'->'inputs'->>'equipment') then
      return jsonb_build_object('kind','request_conflict');
    end if;
    if v_delegated and v_actor->>'kind'<>'user'
      and v_setup->'delegated'->'authority' is distinct from v_current->'delegated'->'authority' then
      return jsonb_build_object('kind','unauthorized_actor');
    end if;
    insert into public.training_program_revisions(id,user_subject,proposal_id,payload,created_at)
      values(v_id,p_subject,v_proposal.id,jsonb_build_object('version',1,'id',v_id,
        'proposal',v_proposal.payload,'setup',v_setup,'activatedAt',v_now),v_now);
    insert into public.native_records(collection,id,user_subject,payload,updated_at)
      values('training_feedback',(v_setup->>'id')::uuid,p_subject,
        v_setup || '{"record_type":"program_setup"}'::jsonb,v_now)
      on conflict(collection,id) do update set payload=excluded.payload,updated_at=excluded.updated_at
      where public.native_records.user_subject=excluded.user_subject and v_delegated
      returning id into v_other;
    if not found then raise exception 'training_setup_not_committed'; end if;
    update public.training_revision_state set head_revision=v_id where user_subject=p_subject;
  end if;
  v_receipt := jsonb_build_object('version',case when v_delegated then 2 else 1 end,'proposalId',v_proposal.id,
    'requestId',(p_request->>'requestId')::uuid,'decision',p_action,
    'status',case when p_action='apply' then 'applied' else 'rejected' end,
    'actor',case when v_delegated then v_actor else jsonb_build_object('kind','self','subject',p_subject) end,
    'priorState',case when v_delegated then v_proposal.payload->'priorState' else 'null'::jsonb end,
    'revisionId',v_id,'setup',v_setup,'decidedAt',v_now);
  update public.training_revision_proposals
    set status=case when p_action='apply' then 'applied' else 'rejected' end,
      decision_id=(p_request->>'requestId')::uuid,decision_hash=p_request->>'requestHash',
      receipt=v_receipt,decided_at=v_now where id=v_proposal.id;
  if v_delegated then update public.training_revision_state set generation=generation+1 where user_subject=p_subject; end if;
  return jsonb_build_object('kind','decided','receipt',v_receipt);
end;
$$;

-- A delegated program has one revision pathway. An older canvas client cannot
-- save a second plan while canonical acceptance races its request.
create or replace function public.training_canvas_save(
  p_subject text, p_owner uuid, p_expected bigint, p_payload jsonb
) returns jsonb language plpgsql as $$
declare
  v_write bigint;
  v_next bigint;
begin
  perform public.lyb_native_account_admit(p_subject, p_owner);
  if exists(select 1 from public.native_records where user_subject=p_subject
    and collection='training_feedback' and deleted_at is null
    and payload->>'record_type'='program_setup' and payload->>'programPolicyVersion'='delegated-canvas-v1') then
    return jsonb_build_object('kind','canonical_revision_required');
  end if;
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

insert into public.schema_migrations(version) values('20261025010000_delegated_training_revisions') on conflict(version) do nothing;
