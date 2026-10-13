-- Add owner incarnation without rewriting historical proposal/export payloads.
create or replace function public.training_revision_context(p_subject text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
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
    if v_head is not null then return jsonb_build_object('kind','program_already_enrolled'); end if;
    if (p_request->'proposal'->'context') is distinct from
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision') then
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
    if v_head is not null then return jsonb_build_object('kind','revision_conflict'); end if;
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
    insert into public.training_program_revisions(id,user_subject,proposal_id,payload,created_at)
      values(v_id,p_subject,v_proposal.id,jsonb_build_object('version',1,'id',v_id,
        'proposal',v_proposal.payload,'setup',v_setup,'activatedAt',v_now),v_now);
    insert into public.native_records(collection,id,user_subject,payload,updated_at)
      values('training_feedback',(v_setup->>'id')::uuid,p_subject,
        v_setup || '{"record_type":"program_setup"}'::jsonb,v_now);
    update public.training_revision_state set head_revision=v_id where user_subject=p_subject;
  end if;
  v_receipt := jsonb_build_object('version',1,'proposalId',v_proposal.id,
    'requestId',(p_request->>'requestId')::uuid,'decision',p_action,
    'status',case when p_action='apply' then 'applied' else 'rejected' end,
    'actor',jsonb_build_object('kind','self','subject',p_subject),'priorState',null,
    'revisionId',v_id,'setup',v_setup,'decidedAt',v_now);
  update public.training_revision_proposals
    set status=case when p_action='apply' then 'applied' else 'rejected' end,
      decision_id=(p_request->>'requestId')::uuid,decision_hash=p_request->>'requestHash',
      receipt=v_receipt,decided_at=v_now where id=v_proposal.id;
  return jsonb_build_object('kind','decided','receipt',v_receipt);
end;
$$;

-- Each call is one transaction, serialized with revision/revoke/delete commands.
create or replace function public.training_mutation_command(
  p_subject text, p_action text, p_admission jsonb, p_record jsonb
) returns jsonb language plpgsql as $$
declare
  v_owner uuid;
  v_context jsonb;
  v_setup public.native_records%rowtype;
  v_session public.native_records%rowtype;
  v_existing public.native_records%rowtype;
  v_saved public.native_records%rowtype;
  v_collection text;
  v_id uuid;
  v_session_id uuid;
  v_payload jsonb;
begin
  select id into v_owner from public.app_users
    where identity_provider='jovie' and identity_subject=p_subject for update;
  if not found then return jsonb_build_object('kind','owner_missing'); end if;
  -- Read after the lock wait; a deleted/recreated subject has a different UUID.
  v_context := public.training_revision_context(p_subject);
  if p_admission->>'ownerId' is distinct from v_owner::text
     or p_admission->'generation' is distinct from v_context->'generation'
     or p_admission->'revisionId' is distinct from v_context->'headRevision' then
    return jsonb_build_object('kind','stale_admission');
  end if;
  select * into v_setup from public.native_records
    where collection='training_feedback' and id=(p_admission->>'setupId')::uuid
      and user_subject=p_subject and deleted_at is null and payload->>'record_type'='program_setup';
  if not found or coalesce(v_setup.payload->'programRevisionId','null'::jsonb)
       is distinct from p_admission->'revisionId' then
    return jsonb_build_object('kind','stale_admission');
  end if;
  if p_action not in ('session_insert','session_update','set_insert','feedback_insert') then
    raise exception 'unsupported_training_mutation';
  end if;
  v_id := (p_record->>'id')::uuid;
  v_payload := p_record - 'user_id' - 'deleted_at' - 'server_updated_at';
  if p_action in ('session_insert','session_update') then
    v_collection := 'training_sessions';
    v_session_id := v_id;
    if p_record->>'record_type' is distinct from 'workout_session'
       or p_record->>'programSetupId' is distinct from v_setup.id::text
       or coalesce(p_record->'programRevisionId','null'::jsonb) is distinct from p_admission->'revisionId' then
      return jsonb_build_object('kind','session_conflict');
    end if;
  else
    v_collection := case when p_action='set_insert' then 'logged_sets' else 'training_feedback' end;
    v_session_id := (p_record->>'sessionId')::uuid;
    if p_record->>'record_type' is distinct from
       (case when p_action='set_insert' then 'set_log' else 'session_feedback' end) then
      return jsonb_build_object('kind','record_conflict');
    end if;
  end if;
  select * into v_session from public.native_records where collection='training_sessions' and id=v_session_id;
  if found then
    if v_session.user_subject<>p_subject or v_session.deleted_at is not null
       or v_session.payload->>'record_type' is distinct from 'workout_session'
       or v_session.payload->>'programSetupId' is distinct from v_setup.id::text
       or coalesce(v_session.payload->'programRevisionId','null'::jsonb) is distinct from p_admission->'revisionId' then
      return jsonb_build_object('kind','session_conflict');
    end if;
  elsif p_action<>'session_insert' then
    return jsonb_build_object('kind','session_conflict');
  end if;

  if p_action='set_insert' then
    -- Preserve accepted identities before checking a potentially reduced effective volume.
    select * into v_existing from public.native_records where collection='logged_sets' and id=v_id;
    if found then
      if v_existing.user_subject<>p_subject or v_existing.deleted_at is not null then
        return jsonb_build_object('kind','record_conflict');
      end if;
      v_saved := v_existing;
    else
      if v_session.payload->>'status' is distinct from 'in_progress'
         or not exists (select 1 from jsonb_array_elements(v_session.payload->'prescription'->'exercises') e
           where e->>'id'=p_record->>'exerciseId'
             and (p_record->>'setNumber')::int between 1 and (e->>'sets')::int) then
        return jsonb_build_object('kind','session_conflict');
      end if;
      insert into public.native_records(collection,id,user_subject,payload,updated_at)
        values(v_collection,v_id,p_subject,v_payload,now())
        on conflict(collection,id) do nothing returning * into v_saved;
      if not found then
        -- Protect globally colliding IDs from another subject, even though owner locks differ.
        select * into v_saved from public.native_records
          where collection=v_collection and id=v_id and user_subject=p_subject and deleted_at is null;
        if not found then return jsonb_build_object('kind','record_conflict'); end if;
      end if;
    end if;
  else
    insert into public.native_records(collection,id,user_subject,payload,updated_at)
      values(v_collection,v_id,p_subject,v_payload,now())
      on conflict(collection,id) do update set payload=excluded.payload,updated_at=now()
        where public.native_records.user_subject=excluded.user_subject
          and public.native_records.deleted_at is null
      returning * into v_saved;
    if not found then return jsonb_build_object('kind','record_conflict'); end if;
  end if;
  return jsonb_build_object('kind','saved','record',v_saved.payload || jsonb_build_object(
    'id',v_saved.id,'user_id',v_saved.user_subject,'deleted_at',v_saved.deleted_at,'server_updated_at',v_saved.updated_at));
end;
$$;

insert into public.schema_migrations(version) values('20261010103000_training_mutation_admission')
on conflict(version) do nothing;
