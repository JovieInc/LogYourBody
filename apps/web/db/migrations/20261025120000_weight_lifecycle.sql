-- Manual weight lifecycle for the delegated agent slice.
-- Wider kilograms keep the shared pound constant. Agent rows are not web
-- daily upserts. Receipts, audit, and grants are deleted with the account
-- and have no foreign keys so cleanup order stays explicit.
-- A native or agent upsert must not clear deleted_at.

alter table public.body_metrics
  alter column weight type numeric(12, 6);

alter table public.body_metrics
  add column if not exists revision integer not null default 1;

alter table public.body_metrics
  drop constraint if exists body_metrics_origin_check;

alter table public.body_metrics
  add constraint body_metrics_origin_check check (origin in ('web', 'native', 'agent'));

create table if not exists public.weight_operation_receipts (
  user_subject text not null,
  operation_id uuid not null,
  request_hash text not null,
  receipt jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_subject, operation_id)
);

create table if not exists public.body_metric_audit (
  id uuid primary key default gen_random_uuid(),
  user_subject text not null,
  record_id uuid not null,
  operation_id uuid not null,
  action text not null,
  revision integer not null,
  created_at timestamptz not null default now(),
  constraint body_metric_audit_action_check check (action in ('create', 'correct', 'delete'))
);

create index if not exists body_metric_audit_subject_record_idx
  on public.body_metric_audit (user_subject, record_id, created_at);

create table if not exists public.metrics_agent_grants (
  user_subject text primary key,
  owner_id uuid not null,
  connected boolean not null default false,
  consent_granted boolean not null default false,
  entitled boolean not null default false,
  revoked_at timestamptz,
  deleted_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists body_metrics_owner_measured_idx
  on public.body_metrics (user_subject, measured_at desc, id desc);

comment on table public.metrics_agent_grants is
  'Explicit per-user admission for delegated weight actions. A missing row is unconnected. Training grants do not write this table.';
comment on table public.weight_operation_receipts is
  'One receipt per subject and operation. A different request hash conflicts and does not write again.';
comment on column public.body_metrics.revision is
  'Increments on a real correction, delete, or newer native payload. Identical retries do not move it.';

-- One statement so the receipt, audit, and row commit or roll back together.
-- Account admission still wraps the call. The function rechecks the owner and grant.
create or replace function public.weight_lifecycle_command(
  p_subject text,
  p_owner uuid,
  p_command jsonb
) returns jsonb
language plpgsql
volatile
as $$
declare
  v_action text;
  v_operation uuid;
  v_record uuid;
  v_hash text;
  v_now timestamptz;
  v_stamp text;
  v_expected integer;
  v_owner uuid;
  v_grant public.metrics_agent_grants%rowtype;
  v_row public.body_metrics%rowtype;
  v_meta jsonb;
  v_revision integer;
  v_deleted timestamptz;
  v_weight text;
  v_input_value text;
  v_input_unit text;
  v_measured text;
  v_offset jsonb;
  v_local_date text;
  v_zone text;
  v_provenance jsonb;
  v_receipt jsonb;
  v_existing_hash text;
  v_existing_receipt jsonb;
begin
  if p_subject is null or btrim(p_subject) = '' or p_owner is null then
    return jsonb_build_object('outcome', 'account_not_found');
  end if;

  select id into v_owner
  from public.app_users
  where identity_provider = 'jovie' and identity_subject = p_subject
  for update;
  if v_owner is null or v_owner is distinct from p_owner then
    return jsonb_build_object('outcome', 'account_not_found');
  end if;

  select * into v_grant
  from public.metrics_agent_grants
  where user_subject = p_subject
  for update;
  if not found or v_grant.connected is not true then
    return jsonb_build_object('outcome', 'unconnected');
  end if;
  if v_grant.revoked_at is not null then
    return jsonb_build_object('outcome', 'revoked');
  end if;
  if v_grant.deleted_at is not null then
    return jsonb_build_object('outcome', 'account_deleted');
  end if;
  if v_grant.owner_id is distinct from p_owner then
    return jsonb_build_object('outcome', 'account_not_found');
  end if;
  if v_grant.consent_granted is not true then
    return jsonb_build_object('outcome', 'consent_required');
  end if;
  if v_grant.entitled is not true then
    return jsonb_build_object('outcome', 'ineligible');
  end if;

  v_action := p_command->>'action';
  v_operation := (p_command->>'operation_id')::uuid;
  v_record := (p_command->>'record_id')::uuid;
  v_hash := p_command->>'request_hash';
  v_now := (p_command->>'now')::timestamptz;
  v_stamp := to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');

  perform pg_advisory_xact_lock(hashtextextended(p_subject || ':' || v_operation::text, 0));

  select request_hash, receipt
  into v_existing_hash, v_existing_receipt
  from public.weight_operation_receipts
  where user_subject = p_subject and operation_id = v_operation;
  if found then
    if v_existing_hash is distinct from v_hash then
      return jsonb_build_object('outcome', 'idempotency_conflict');
    end if;
    return jsonb_build_object('outcome', 'replayed', 'receipt', v_existing_receipt);
  end if;

  if v_action = 'create' then
    select * into v_row from public.body_metrics where id = v_record for update;
    if found then
      return jsonb_build_object('outcome', 'record_conflict');
    end if;
    insert into public.body_metrics (
      id, user_subject, date, measured_at, local_date, origin,
      weight, weight_unit, data_source, source_metadata,
      client_created_at, client_updated_at, deleted_at, revision,
      created_at, updated_at
    ) values (
      v_record,
      p_subject,
      (p_command->>'local_date')::date,
      (p_command->>'measured_at')::timestamptz,
      (p_command->>'local_date')::date,
      'agent',
      (p_command->>'weight_kg')::numeric,
      'kg',
      'manual',
      jsonb_strip_nulls(jsonb_build_object(
        'weight_operation_id', v_operation,
        'weight_revision', 1,
        'weight_kg', p_command->>'weight_kg',
        'input_value', p_command->>'input_value',
        'input_unit', p_command->>'input_unit',
        'measured_at', p_command->>'measured_at',
        'utc_offset_minutes', p_command->'utc_offset_minutes',
        'local_date', p_command->>'local_date',
        'iana_zone', p_command->>'iana_zone',
        'provenance', p_command->'provenance'
      )),
      v_now,
      v_now,
      null,
      1,
      v_now,
      v_now
    );
    v_revision := 1;
    v_deleted := null;
    v_weight := p_command->>'weight_kg';
    v_input_value := p_command->>'input_value';
    v_input_unit := p_command->>'input_unit';
    v_measured := p_command->>'measured_at';
    v_offset := p_command->'utc_offset_minutes';
    v_local_date := p_command->>'local_date';
    v_zone := p_command->>'iana_zone';
    v_provenance := p_command->'provenance';
  elsif v_action = 'correct' or v_action = 'delete' then
    v_expected := (p_command->>'expected_revision')::integer;
    select * into v_row from public.body_metrics where id = v_record for update;
    if not found or v_row.user_subject is distinct from p_subject then
      return jsonb_build_object('outcome', 'not_found');
    end if;
    if v_row.revision is distinct from v_expected then
      return jsonb_build_object('outcome', 'stale_revision');
    end if;
    if v_row.deleted_at is not null then
      return jsonb_build_object('outcome', 'already_deleted');
    end if;
    v_meta := coalesce(v_row.source_metadata, '{}'::jsonb);
    if v_action = 'correct' then
      update public.body_metrics set
        date = (p_command->>'local_date')::date,
        measured_at = (p_command->>'measured_at')::timestamptz,
        local_date = (p_command->>'local_date')::date,
        weight = (p_command->>'weight_kg')::numeric,
        weight_unit = 'kg',
        source_metadata = v_meta || jsonb_strip_nulls(jsonb_build_object(
          'weight_operation_id', v_operation,
          'weight_revision', v_row.revision + 1,
          'weight_kg', p_command->>'weight_kg',
          'input_value', p_command->>'input_value',
          'input_unit', p_command->>'input_unit',
          'measured_at', p_command->>'measured_at',
          'utc_offset_minutes', p_command->'utc_offset_minutes',
          'local_date', p_command->>'local_date',
          'iana_zone', p_command->>'iana_zone',
          'provenance', p_command->'provenance'
        )),
        client_updated_at = v_now,
        updated_at = v_now,
        revision = v_row.revision + 1
      where id = v_record;
      v_revision := v_row.revision + 1;
      v_deleted := null;
      v_weight := p_command->>'weight_kg';
      v_input_value := p_command->>'input_value';
      v_input_unit := p_command->>'input_unit';
      v_measured := p_command->>'measured_at';
      v_offset := p_command->'utc_offset_minutes';
      v_local_date := p_command->>'local_date';
      v_zone := p_command->>'iana_zone';
      v_provenance := p_command->'provenance';
    else
      update public.body_metrics set
        deleted_at = v_now,
        client_updated_at = v_now,
        updated_at = v_now,
        revision = v_row.revision + 1,
        source_metadata = v_meta || jsonb_build_object(
          'weight_operation_id', v_operation,
          'weight_revision', v_row.revision + 1
        )
      where id = v_record;
      v_revision := v_row.revision + 1;
      v_deleted := v_now;
      v_weight := coalesce(v_meta->>'weight_kg', trim(to_char(v_row.weight, 'FM999990.000000')));
      v_input_value := coalesce(v_meta->>'input_value', v_weight);
      v_input_unit := coalesce(v_meta->>'input_unit', 'kg');
      v_measured := coalesce(
        v_meta->>'measured_at',
        to_char(v_row.measured_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      );
      v_offset := coalesce(v_meta->'utc_offset_minutes', '0'::jsonb);
      v_local_date := coalesce(v_meta->>'local_date', to_char(v_row.local_date, 'YYYY-MM-DD'));
      v_zone := coalesce(v_meta->>'iana_zone', 'UTC');
      v_provenance := coalesce(
        v_meta->'provenance',
        jsonb_build_object(
          'actor', 'device',
          'conversion', 'identity',
          'constant', '0.45359237',
          'canonical_kg', v_weight
        )
      );
    end if;
  else
    return jsonb_build_object('outcome', 'invalid_input', 'reason', 'rejected_shape');
  end if;

  v_receipt := jsonb_build_object(
    'operation_id', v_operation,
    'action', v_action,
    'record', jsonb_build_object(
      'id', v_record,
      'revision', v_revision,
      'weight_kg', v_weight,
      'input', jsonb_build_object('value', v_input_value, 'unit', v_input_unit),
      'measured_at', v_measured,
      'utc_offset_minutes', v_offset,
      'local_date', v_local_date,
      'iana_zone', v_zone,
      'deleted_at', case when v_deleted is null then null::jsonb else to_jsonb(v_stamp) end,
      'provenance', v_provenance
    ),
    'cloud', jsonb_build_object('status', 'committed', 'server_updated_at', v_stamp),
    'device', jsonb_build_object('healthkit', 'not_claimed')
  );

  insert into public.weight_operation_receipts (user_subject, operation_id, request_hash, receipt)
  values (p_subject, v_operation, v_hash, v_receipt);
  insert into public.body_metric_audit (user_subject, record_id, operation_id, action, revision)
  values (p_subject, v_record, v_operation, v_action, v_revision);

  return jsonb_build_object('outcome', 'committed', 'receipt', v_receipt);
exception
  when invalid_text_representation then
    return jsonb_build_object('outcome', 'invalid_input', 'reason', 'invalid_id');
  when unique_violation then
    return jsonb_build_object('outcome', 'record_conflict');
end;
$$;

insert into public.schema_migrations (version)
values ('20261025120000_weight_lifecycle')
on conflict (version) do nothing;
