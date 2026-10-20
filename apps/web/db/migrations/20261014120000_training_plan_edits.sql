-- Typed plan-edit revisions (LYB-164). A plan_edit proposal builds on the live
-- head revision, installs a canonical weekly layout, and moves head forward;
-- the enrolled setup row rebinds to the new head so mutation admission and
-- workout execution keep agreeing with the stored plan.

-- The immutable payload of the subject's current head revision, or null.
create or replace function public.training_head_revision(p_subject text)
returns jsonb language sql stable as $$
  select r.payload from public.training_revision_state s
    join public.training_program_revisions r on r.id = s.head_revision
  where s.user_subject = p_subject;
$$;

create or replace function public.training_revision_command(p_subject text, p_action text, p_request jsonb)
returns jsonb language plpgsql as $$
declare
  v_owner uuid;
  v_context jsonb;
  v_proposal public.training_revision_proposals%rowtype;
  v_generation bigint;
  v_head uuid;
  v_head_payload jsonb;
  v_setup jsonb;
  v_receipt jsonb;
  v_id uuid;
  v_other uuid;
  v_count integer;
  v_now timestamptz;
  v_base text;
  v_prior uuid;
  v_layout jsonb;
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
    v_base := p_request->'proposal'->>'baseRevision';
    if v_base is null then
      -- Initial enrollment is only valid before a canonical head exists.
      if v_head is not null then return jsonb_build_object('kind','program_already_enrolled'); end if;
    else
      -- A plan edit may only be proposed against the live head revision.
      if v_head is null then return jsonb_build_object('kind','program_not_enrolled'); end if;
      if v_head::text is distinct from v_base then
        return jsonb_build_object('kind','revision_conflict');
      end if;
    end if;
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
  v_setup := null;
  v_prior := null;
  v_base := v_proposal.payload->>'baseRevision';
  if p_action='apply' then
    if v_proposal.payload->'context' is distinct from
      (v_context - 'dateOfBirth' - 'legacySetups' - 'headRevision') then
      return jsonb_build_object('kind','stale_context');
    end if;
    v_id := (p_request->>'revisionId')::uuid;
    if v_base is null then
      -- Initial enrollment: exactly one revision may install the program.
      if v_head is not null then return jsonb_build_object('kind','revision_conflict'); end if;
      v_setup := p_request->'setup';
      if v_setup->>'id' is distinct from v_proposal.payload->>'programId'
         or v_setup->>'programRevisionId' is distinct from v_id::text then
        return jsonb_build_object('kind','request_conflict');
      end if;
      insert into public.training_program_revisions(id,user_subject,proposal_id,payload,created_at)
        values(v_id,p_subject,v_proposal.id,jsonb_build_object('version',1,'id',v_id,
          'proposal',v_proposal.payload,'baseRevision',null,'layout',null,
          'setup',v_setup,'activatedAt',v_now),v_now);
      insert into public.native_records(collection,id,user_subject,payload,updated_at)
        values('training_feedback',(v_setup->>'id')::uuid,p_subject,
          v_setup || '{"record_type":"program_setup"}'::jsonb,v_now);
      update public.training_revision_state set head_revision=v_id where user_subject=p_subject;
    else
      -- Plan edit: the stored proposal's baseRevision must still be head.
      if v_head is null or v_head::text is distinct from v_base then
        return jsonb_build_object('kind','revision_conflict');
      end if;
      if p_request->>'baseRevision' is distinct from v_base then
        return jsonb_build_object('kind','request_conflict');
      end if;
      v_layout := p_request->'layout';
      if v_layout is null then return jsonb_build_object('kind','request_conflict'); end if;
      select payload into v_head_payload from public.training_program_revisions
        where id=v_head and user_subject=p_subject;
      if not found then return jsonb_build_object('kind','revision_conflict'); end if;
      if v_head_payload->'setup'->>'id' is distinct from v_proposal.payload->>'programId' then
        return jsonb_build_object('kind','request_conflict');
      end if;
      v_prior := v_head;
      insert into public.training_program_revisions(id,user_subject,proposal_id,payload,created_at)
        values(v_id,p_subject,v_proposal.id,jsonb_build_object('version',1,'id',v_id,
          'proposal',v_proposal.payload,'baseRevision',v_head,'layout',v_layout,
          'setup',v_head_payload->'setup' || jsonb_build_object('programRevisionId',v_id),
          'activatedAt',v_now),v_now);
      -- One canonical layout per program: supersede the previous one in the
      -- same transaction so the canvas and workout execution never disagree.
      update public.native_records set deleted_at=v_now,updated_at=v_now
        where user_subject=p_subject and collection='training_sessions' and deleted_at is null
          and payload->>'record_type'='plan_layout'
          and payload->>'programSetupId' is not distinct from v_proposal.payload->>'programId';
      insert into public.native_records(collection,id,user_subject,payload,updated_at)
        values('training_sessions',v_id,p_subject,jsonb_build_object(
          'record_type','plan_layout',
          'programSetupId',v_proposal.payload->>'programId',
          'programRevisionId',v_id,
          'layout',v_layout,'createdAt',v_now),v_now);
      -- Rebind the enrolled setup to the new head so the mutation admission
      -- (revisionId must equal head_revision) keeps working after an edit.
      update public.native_records set
          payload = payload || jsonb_build_object('programRevisionId', v_id),
          updated_at = v_now
        where collection='training_feedback' and id=(v_proposal.payload->>'programId')::uuid
          and user_subject=p_subject and payload->>'record_type'='program_setup'
          and deleted_at is null;
      if not found then return jsonb_build_object('kind','revision_conflict'); end if;
      update public.training_revision_state set head_revision=v_id where user_subject=p_subject;
    end if;
  end if;
  v_receipt := jsonb_build_object('version',1,'proposalId',v_proposal.id,
    'requestId',(p_request->>'requestId')::uuid,'decision',p_action,
    'status',case when p_action='apply' then 'applied' else 'rejected' end,
    'actor',jsonb_build_object('kind','self','subject',p_subject),'priorState',v_prior,
    'revisionId',v_id,'setup',v_setup,'decidedAt',v_now);
  update public.training_revision_proposals
    set status=case when p_action='apply' then 'applied' else 'rejected' end,
      decision_id=(p_request->>'requestId')::uuid,decision_hash=p_request->>'requestHash',
      receipt=v_receipt,decided_at=v_now where id=v_proposal.id;
  return jsonb_build_object('kind','decided','receipt',v_receipt);
end;
$$;

insert into public.schema_migrations(version) values('20261014120000_training_plan_edits')
on conflict(version) do nothing;
