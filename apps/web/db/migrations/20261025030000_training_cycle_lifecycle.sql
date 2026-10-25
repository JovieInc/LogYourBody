-- Lifecycle revisions use the existing owner-locked proposal/decision transaction.
-- The fingerprint includes training attempts, logs and feedback so a held draft
-- cannot be applied over training accepted since review.
create or replace function public.training_cycle_fingerprint(p_subject text)
returns text language sql stable as $$
  select md5(coalesce(jsonb_agg(jsonb_build_object('collection',collection,'id',id,'payload',payload)
    order by collection,id)::text,'[]')) from public.native_records
    where user_subject=p_subject and deleted_at is null
      and collection in ('training_sessions','logged_sets','training_feedback');
$$;
create or replace function public.training_revision_context(p_subject text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'trainingFingerprint', public.training_cycle_fingerprint(p_subject),
    'ownerId', u.id, 'generation', coalesce(s.generation,0), 'headRevision', s.head_revision,
    'profileFingerprint', md5(coalesce(u.profile_data,'{}'::jsonb)::text),
    'dateOfBirth', u.profile_data->'date_of_birth',
    'legacyFingerprint', public.training_legacy_setup_fingerprint(p_subject),
    'legacySetups', coalesce((select jsonb_agg(n.payload || jsonb_build_object('id',n.id))
      from public.native_records n where n.user_subject=p_subject and n.collection='training_feedback'
        and n.deleted_at is null and n.payload->>'record_type'='program_setup'), '[]'::jsonb))
  from public.app_users u left join public.training_revision_state s on s.user_subject=u.identity_subject
  where u.identity_provider='jovie' and u.identity_subject=p_subject;
$$;

-- Replace the command additively; the foundation migration may already be deployed.
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
begin
  select id into v_owner from public.app_users
    where identity_provider='jovie' and identity_subject=p_subject for update;
  if not found then return jsonb_build_object('kind','owner_missing'); end if;
  v_context := public.training_revision_context(p_subject);
  v_generation := (v_context->>'generation')::bigint;
  v_head := (v_context->>'headRevision')::uuid;

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
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision' - 'trainingFingerprint') then
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
    if p_request->'proposal'->>'proposedDiff' in ('revise_cycle','repeat_cycle') then
      if (p_request->'proposal'->>'baseRevision')::uuid is distinct from v_head then
        return jsonb_build_object('kind','revision_conflict');
      end if;
      if p_request->'proposal'->>'trainingFingerprint' is distinct from v_context->>'trainingFingerprint' then
        return jsonb_build_object('kind','stale_context');
      end if;
    elsif v_head is not null then return jsonb_build_object('kind','program_already_enrolled'); end if;
    if (p_request->'proposal'->'context') is distinct from
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision' - 'trainingFingerprint') then
      return jsonb_build_object('kind','stale_context');
    end if;
    if p_request->'proposal'->'actor'->>'subject' is distinct from p_subject then
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
    where user_subject=p_subject and decision_id=(p_request->>'requestId')::uuid;
  if found and v_other<>(p_request->>'proposalId')::uuid then
    return jsonb_build_object('kind','request_conflict');
  end if;
  select * into v_proposal from public.training_revision_proposals
    where id=(p_request->>'proposalId')::uuid and user_subject=p_subject for update;
  if not found then return jsonb_build_object('kind','proposal_not_found'); end if;
  -- A held decision cannot target a recreated owner's identical deterministic ID.
  if p_request->'context'->>'ownerId' is distinct from v_owner::text
     or p_request->'context'->'generation' is distinct from v_context->'generation' then
    return jsonb_build_object('kind','stale_context');
  end if;
  if v_proposal.decision_id=(p_request->>'requestId')::uuid then
    if v_proposal.decision_hash<>p_request->>'requestHash' then
      return jsonb_build_object('kind','request_conflict');
    end if;
    return jsonb_build_object('kind','decided','receipt',v_proposal.receipt);
  end if;
  if v_proposal.status<>'proposed' then return jsonb_build_object('kind','already_decided'); end if;
  -- Legacy proposals remain readable/exportable but cannot authorize new writes.
  if v_proposal.payload->'context'->>'ownerId' is distinct from v_owner::text then
    return jsonb_build_object('kind','stale_context');
  end if;
  if v_generation<>v_proposal.generation then return jsonb_build_object('kind','stale_context'); end if;
  v_now := (p_request->>'now')::timestamptz;
  if p_action='apply' then
    if (v_proposal.payload->>'baseRevision')::uuid is distinct from v_head then
      return jsonb_build_object('kind','revision_conflict');
    end if;
    if v_proposal.payload->>'proposedDiff' in ('revise_cycle','repeat_cycle') then
      if v_proposal.payload->>'trainingFingerprint' is distinct from v_context->>'trainingFingerprint'
        or (v_proposal.payload->>'proposedDiff'='repeat_cycle' and exists (select 1 from public.native_records where user_subject=p_subject
          and collection='training_sessions' and deleted_at is null
          and payload->>'programSetupId'=v_proposal.payload->'priorState'->>'setupId'
          and payload->>'status' in ('in_progress','paused'))) then
        return jsonb_build_object('kind','stale_context');
      end if;
      if ((p_request->'setup') - 'programRevisionId' - 'startedAt') is distinct from
         ((v_proposal.payload->'proposedSetup') - 'startedAt') then
        return jsonb_build_object('kind','request_conflict');
      end if;
      if p_request->'setup'->>'startedAt' is distinct from
        (case when v_proposal.payload->>'proposedDiff'='repeat_cycle' then p_request->>'now'
          else v_proposal.payload->'proposedSetup'->>'startedAt' end) then
        return jsonb_build_object('kind','request_conflict');
      end if;
    end if;
    if v_proposal.payload->'context' is distinct from
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision' - 'trainingFingerprint') then
      return jsonb_build_object('kind','stale_context');
    end if;
    v_id := (p_request->>'revisionId')::uuid;
    v_setup := p_request->'setup';
    if v_setup->>'id' is distinct from v_proposal.payload->>'programId'
       or v_setup->>'programRevisionId' is distinct from v_id::text then
      return jsonb_build_object('kind','request_conflict');
    end if;
    insert into public.training_program_revisions(id,user_subject,proposal_id,payload,created_at)
      values(v_id,p_subject,v_proposal.id,jsonb_build_object('version',1,'id',v_id,
        'proposal',v_proposal.payload,'setup',v_setup,'activatedAt',v_now),v_now);
    insert into public.native_records(collection,id,user_subject,payload,updated_at)
      values('training_feedback',(v_setup->>'id')::uuid,p_subject,
        v_setup || '{"record_type":"program_setup"}'::jsonb,v_now)
      on conflict(collection,id) do update set payload=excluded.payload,updated_at=excluded.updated_at
        where public.native_records.user_subject=p_subject and public.native_records.deleted_at is null
          and v_proposal.payload->>'proposedDiff'='revise_cycle'
          and public.native_records.payload->>'programRevisionId' is not distinct from (v_head::text)
      returning id into v_other;
    if not found then raise exception 'training_cycle_setup_conflict'; end if;
    -- Rebind active attempts to the reviewed head without rebuilding their saved
    -- prescription. Held writes using the previous admission fail after this lock.
    if v_proposal.payload->>'proposedDiff'='revise_cycle' then
      update public.native_records set payload=jsonb_set(payload,'{programRevisionId}',to_jsonb(v_id)),updated_at=v_now
        where user_subject=p_subject and collection='training_sessions' and deleted_at is null
          and payload->>'programSetupId'=v_setup->>'id'
          and payload->>'status' in ('in_progress','paused');
    end if;
    update public.training_revision_state set head_revision=v_id where user_subject=p_subject;
  end if;
  v_receipt := jsonb_build_object('version',1,'proposalId',v_proposal.id,
    'requestId',(p_request->>'requestId')::uuid,'decision',p_action,
    'status',case when p_action='apply' then 'applied' else 'rejected' end,
    'actor',jsonb_build_object('kind','self','subject',p_subject),'priorState',v_proposal.payload->'priorState',
    'revisionId',v_id,'setup',v_setup,'decidedAt',v_now);
  update public.training_revision_proposals
    set status=case when p_action='apply' then 'applied' else 'rejected' end,
      decision_id=(p_request->>'requestId')::uuid,decision_hash=p_request->>'requestHash',
      receipt=v_receipt,decided_at=v_now where id=v_proposal.id;
  return jsonb_build_object('kind','decided','receipt',v_receipt);
end;
$$;


insert into public.schema_migrations(version) values('20261025030000_training_cycle_lifecycle') on conflict(version) do nothing;
