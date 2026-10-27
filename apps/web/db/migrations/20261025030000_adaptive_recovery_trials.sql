-- Recovery trials live in the existing training record collection so export,
-- consent revocation and account deletion retain their existing ownership.
-- Serialize source validation and trial CAS with the canonical owner lock.
create or replace function public.training_recovery_trial_command(
  p_subject text, p_admission jsonb, p_expected_records jsonb,
  p_expected_revision integer, p_record jsonb
) returns jsonb language plpgsql as $$
declare
  v_owner uuid;
  v_context jsonb;
  v_setup public.native_records%rowtype;
  v_prior public.native_records%rowtype;
  v_saved public.native_records%rowtype;
  v_basis jsonb;
  v_payload jsonb;
  v_state text;
begin
  select id into v_owner from public.app_users
    where identity_provider='jovie' and identity_subject=p_subject for update;
  if not found then return jsonb_build_object('kind','owner_missing'); end if;
  v_context := public.training_revision_context(p_subject);
  if p_admission->>'ownerId' is distinct from v_owner::text
     or p_admission->'generation' is distinct from v_context->'generation'
     or p_admission->'revisionId' is distinct from v_context->'headRevision' then
    return jsonb_build_object('kind','stale_admission');
  end if;
  select * into v_setup from public.native_records where collection='training_feedback'
    and id=(p_admission->>'setupId')::uuid and user_subject=p_subject
    and deleted_at is null and payload->>'record_type'='program_setup';
  if not found or coalesce(v_setup.payload->'programRevisionId','null'::jsonb)
      is distinct from p_admission->'revisionId' then
    return jsonb_build_object('kind','stale_admission');
  end if;
  select coalesce(jsonb_object_agg(collection || '/' || id::text,
    payload || jsonb_build_object('id',id)), '{}'::jsonb) into v_basis
    from public.native_records where user_subject=p_subject and deleted_at is null
      and collection in ('training_sessions','logged_sets','training_feedback');
  if v_basis is distinct from p_expected_records then
    return jsonb_build_object('kind','record_conflict');
  end if;
  v_payload := p_record - 'user_id' - 'deleted_at' - 'server_updated_at';
  if v_payload->>'record_type' is distinct from 'recovery_trial'
     or v_payload->>'policyVersion' is distinct from 'adaptive-recovery-v1'
     or v_payload->>'programSetupId' is distinct from v_setup.id::text
     or v_payload->'programRevisionId' is distinct from p_admission->'revisionId' then
    return jsonb_build_object('kind','record_conflict');
  end if;
  select * into v_prior from public.native_records
    where collection='training_feedback' and id=(p_record->>'id')::uuid;
  v_state := v_payload->>'state';
  if found then
    if v_prior.user_subject<>p_subject or v_prior.deleted_at is not null
       or v_prior.payload->>'record_type' is distinct from 'recovery_trial'
       or p_expected_revision is null
       or (v_prior.payload->>'revision')::integer is distinct from p_expected_revision
       or (v_payload->>'revision')::integer is distinct from p_expected_revision+1
       -- Original prescription, observations, inference and proposal are immutable.
       or (v_payload - array['revision','state','outcome','history','updatedAt','appliedAt'])
          is distinct from (v_prior.payload - array['revision','state','outcome','history','updatedAt','appliedAt'])
       or jsonb_array_length(v_payload->'history') is distinct from p_expected_revision+2
       or ((v_payload->'history') - (p_expected_revision+1)) is distinct from v_prior.payload->'history'
       or not ((v_prior.payload->>'state'='proposed' and v_state in ('applied','rejected'))
         or (v_prior.payload->>'state'='applied' and v_state in ('applied','reverted'))) then
      return jsonb_build_object('kind','record_conflict');
    end if;
  elsif p_expected_revision is not null or (v_payload->>'revision')::integer is distinct from 0
      or v_state is distinct from 'proposed' then
    return jsonb_build_object('kind','record_conflict');
  end if;
  if v_state='applied' then
    if v_payload->'inference'->>'action' is distinct from 'reduce'
       or (v_payload->'inference'->'change'->>'to')::integer is distinct from 1
       or coalesce((v_payload->'inference'->'change'->>'from')::integer,0)<=1
       or exists (select 1 from public.native_records n
         where n.collection='training_feedback' and n.user_subject=p_subject and n.deleted_at is null
           and n.id<>(p_record->>'id')::uuid and n.payload->>'record_type'='recovery_trial'
           and n.payload->>'state'='applied'
           and n.payload->>'programSetupId'=v_payload->>'programSetupId'
           and n.payload->>'blockId'=v_payload->>'blockId'
           and n.payload->>'exerciseId'=v_payload->>'exerciseId') then
      return jsonb_build_object('kind','record_conflict');
    end if;
  end if;
  insert into public.native_records(collection,id,user_subject,payload,updated_at)
    values('training_feedback',(p_record->>'id')::uuid,p_subject,v_payload,now())
    on conflict(collection,id) do update set payload=excluded.payload,updated_at=excluded.updated_at
      where public.native_records.user_subject=excluded.user_subject and public.native_records.deleted_at is null
    returning * into v_saved;
  if not found then return jsonb_build_object('kind','record_conflict'); end if;
  return jsonb_build_object('kind','saved','record',v_saved.payload || jsonb_build_object(
    'id',v_saved.id,'user_id',v_saved.user_subject,'deleted_at',v_saved.deleted_at,'server_updated_at',v_saved.updated_at));
end;
$$;

insert into public.schema_migrations(version) values('20261025030000_adaptive_recovery_trials')
on conflict(version) do nothing;
