-- Session actions and set corrections stay inside the owner lock. Optional
-- compare-and-swap fields are stripped before the payload is stored.
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
  v_logged_sets integer;
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
  if p_action not in ('session_insert','session_update','set_insert','set_correct','feedback_insert','swap_insert') then
    raise exception 'unsupported_training_mutation';
  end if;
  v_id := (p_record->>'id')::uuid;
  v_payload := p_record - 'user_id' - 'deleted_at' - 'server_updated_at'
    - 'expectedRevision' - 'expectedExecutionRevision' - 'expectedLoggedSetCount';
  if p_action in ('session_insert','session_update') then
    v_collection := 'training_sessions';
    v_session_id := v_id;
    if p_record->>'record_type' is distinct from 'workout_session'
       or p_record->>'programSetupId' is distinct from v_setup.id::text
       or coalesce(p_record->'programRevisionId','null'::jsonb) is distinct from p_admission->'revisionId' then
      return jsonb_build_object('kind','session_conflict');
    end if;
  elsif p_action='swap_insert' then
    v_collection := 'training_sessions';
    v_session_id := (p_record->>'sessionId')::uuid;
    if p_record->>'record_type' is distinct from 'exercise_swap'
       or p_record->>'programSetupId' is distinct from v_setup.id::text
       or coalesce(p_record->'programRevisionId','null'::jsonb) is distinct from p_admission->'revisionId'
       or p_record->>'fromExerciseId' is null
       or p_record->>'toVariantId' is null
       or p_record->>'blockId' is null then
      return jsonb_build_object('kind','record_conflict');
    end if;
  elsif p_action='set_correct' then
    v_collection := 'logged_sets';
    v_session_id := (p_record->>'sessionId')::uuid;
    if p_record->>'record_type' is distinct from 'set_log'
       or p_record->>'expectedRevision' is null
       or p_record->>'sessionId' is null then
      return jsonb_build_object('kind','record_conflict');
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
  if p_action='swap_insert' and v_session.payload->>'status' is distinct from 'in_progress' then
    return jsonb_build_object('kind','session_conflict');
  end if;

  if p_action='session_update'
     and (p_record ? 'expectedExecutionRevision' or p_record ? 'expectedLoggedSetCount') then
    select count(*) into v_logged_sets from public.native_records logged
      where logged.collection='logged_sets' and logged.user_subject=p_subject
        and logged.deleted_at is null and logged.payload->>'sessionId'=v_session_id::text;
    if coalesce((v_session.payload->'prescription'->>'executionRevision')::integer, 0)
         is distinct from (p_record->>'expectedExecutionRevision')::integer
       or v_logged_sets is distinct from (p_record->>'expectedLoggedSetCount')::integer then
      return jsonb_build_object('kind','record_conflict');
    end if;
  end if;

  if p_action='set_correct' then
    select * into v_existing from public.native_records where collection='logged_sets' and id=v_id;
    if not found or v_existing.user_subject<>p_subject or v_existing.deleted_at is not null
       or v_existing.payload->>'sessionId' is distinct from v_session_id::text
       or coalesce((v_existing.payload->>'revision')::integer, 0)
          is distinct from (p_record->>'expectedRevision')::integer then
      return jsonb_build_object('kind','record_conflict');
    end if;
    update public.native_records
      set payload=v_payload, updated_at=now()
      where collection='logged_sets' and id=v_id
        and user_subject=p_subject and deleted_at is null
        and coalesce((payload->>'revision')::integer, 0)=(p_record->>'expectedRevision')::integer
      returning * into v_saved;
    if not found then return jsonb_build_object('kind','record_conflict'); end if;
  elsif p_action='set_insert' then
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

insert into public.schema_migrations(version) values('20261014103000_training_execution_cas')
on conflict(version) do nothing;
