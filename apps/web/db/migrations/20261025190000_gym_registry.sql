-- User-confirmed gyms. Equipment is only what the user saved on the row.
-- There are no location columns and no inferred inventory. The active gym
-- stays on the device until the user selects one. This is the Neon table for
-- that registry; row level security isolates subjects for non-owner roles.

create or replace function public.gym_preferred_machines_ok(machines text[])
returns boolean
language plpgsql
immutable
as $$
declare
  machine text;
begin
  if machines is null or cardinality(machines) > 24 then
    return false;
  end if;
  foreach machine in array machines loop
    if machine is null or char_length(machine) < 1 or char_length(machine) > 80 then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create table if not exists public.gyms (
  id uuid primary key,
  user_subject text not null,
  name text not null,
  region text,
  equipment text[] not null default '{}',
  preferred_machines text[] not null default '{}',
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint gyms_subject_check check (char_length(btrim(user_subject)) between 1 and 200),
  constraint gyms_name_check check (char_length(name) between 1 and 80),
  constraint gyms_region_check check (region is null or char_length(region) between 1 and 80),
  constraint gyms_equipment_check check (
    equipment <@ array[
      'dumbbells', 'barbell', 'ez_bar', 'machine', 'cable',
      'bench', 'adjustable_bench', 'bodyweight', 'smith'
    ]::text[]
  ),
  constraint gyms_machines_check check (public.gym_preferred_machines_ok(preferred_machines))
);

create index if not exists gyms_owner_updated_idx
  on public.gyms (user_subject, updated_at asc, id asc);

comment on table public.gyms is
  'Subject-scoped gyms the user registered. Equipment and preferred machines are explicit. No location and no inferred inventory.';

alter table public.gyms enable row level security;
alter table public.gyms force row level security;

drop policy if exists gyms_select_own on public.gyms;
create policy gyms_select_own on public.gyms
  for select
  using (user_subject = nullif(current_setting('app.current_user_subject', true), ''));

drop policy if exists gyms_insert_own on public.gyms;
create policy gyms_insert_own on public.gyms
  for insert
  with check (user_subject = nullif(current_setting('app.current_user_subject', true), ''));

drop policy if exists gyms_update_own on public.gyms;
create policy gyms_update_own on public.gyms
  for update
  using (user_subject = nullif(current_setting('app.current_user_subject', true), ''))
  with check (user_subject = nullif(current_setting('app.current_user_subject', true), ''));

drop policy if exists gyms_delete_own on public.gyms;
create policy gyms_delete_own on public.gyms
  for delete
  using (user_subject = nullif(current_setting('app.current_user_subject', true), ''));

create or replace function public.lyb_list_gyms()
returns setof public.gyms
language sql
stable
as $$
  select *
  from public.gyms
  where user_subject = nullif(current_setting('app.current_user_subject', true), '')
  order by updated_at asc, id asc;
$$;

create or replace function public.lyb_upsert_gym(
  p_id uuid,
  p_name text,
  p_region text,
  p_equipment text[],
  p_preferred_machines text[]
) returns public.gyms
language plpgsql
as $$
declare
  v_subject text := nullif(current_setting('app.current_user_subject', true), '');
  v_name text := btrim(coalesce(p_name, ''));
  v_region text := nullif(btrim(coalesce(p_region, '')), '');
  v_equipment text[];
  v_machines text[];
  v_row public.gyms;
begin
  if v_subject is null then
    raise exception 'gym_subject_required' using errcode = '42501';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 80 then
    raise exception 'invalid_gym_name' using errcode = '22023';
  end if;
  if v_region is not null and char_length(v_region) > 80 then
    raise exception 'invalid_gym_region' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct item order by item), '{}')
    into v_equipment
  from unnest(coalesce(p_equipment, '{}'::text[])) as item;

  if exists (
    select 1 from unnest(v_equipment) item
    where item not in (
      'dumbbells', 'barbell', 'ez_bar', 'machine', 'cable',
      'bench', 'adjustable_bench', 'bodyweight', 'smith'
    )
  ) then
    raise exception 'invalid_gym_equipment' using errcode = '22023';
  end if;

  select coalesce(array_agg(machine order by ord), '{}')
    into v_machines
  from (
    select btrim(machine) as machine, min(ord) as ord
    from unnest(coalesce(p_preferred_machines, '{}'::text[])) with ordinality as listed(machine, ord)
    where btrim(machine) <> ''
    group by btrim(machine)
  ) deduped;

  if cardinality(v_machines) > 24 or exists (
    select 1 from unnest(v_machines) machine
    where char_length(machine) > 80
  ) then
    raise exception 'invalid_gym_machine' using errcode = '22023';
  end if;

  begin
    insert into public.gyms (
      id, user_subject, name, region, equipment, preferred_machines, deleted_at, updated_at
    ) values (
      p_id, v_subject, v_name, v_region, v_equipment, v_machines, null, now()
    )
    on conflict (id) do update set
      name = excluded.name,
      region = excluded.region,
      equipment = excluded.equipment,
      preferred_machines = excluded.preferred_machines,
      deleted_at = null,
      updated_at = now()
    where public.gyms.user_subject = v_subject
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'gym_not_owned' using errcode = '42501';
  end;

  if v_row.id is null then
    raise exception 'gym_not_owned' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

create or replace function public.lyb_delete_gym(p_id uuid)
returns public.gyms
language plpgsql
as $$
declare
  v_subject text := nullif(current_setting('app.current_user_subject', true), '');
  v_row public.gyms;
begin
  if v_subject is null then
    raise exception 'gym_subject_required' using errcode = '42501';
  end if;
  update public.gyms
    set deleted_at = coalesce(deleted_at, now()),
        updated_at = now()
    where id = p_id and user_subject = v_subject
    returning * into v_row;
  if v_row.id is null then
    raise exception 'gym_not_owned' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

-- Account removal. The server passes the admitted subject. The function sets
-- the same row-level-security subject before deleting, so a forced policy
-- still removes that subject's rows and no others.
create or replace function public.lyb_delete_my_gyms(p_subject text)
returns void
language plpgsql
as $$
declare
  v_subject text := nullif(btrim(coalesce(p_subject, '')), '');
begin
  if v_subject is null then
    raise exception 'gym_subject_required' using errcode = '42501';
  end if;
  perform set_config('app.current_user_subject', v_subject, true);
  delete from public.gyms where user_subject = v_subject;
end;
$$;

revoke all on function public.lyb_list_gyms() from public;
revoke all on function public.lyb_upsert_gym(uuid, text, text, text[], text[]) from public;
revoke all on function public.lyb_delete_gym(uuid) from public;
revoke all on function public.lyb_delete_my_gyms(text) from public;

insert into public.schema_migrations (version)
values ('20261025190000_gym_registry')
on conflict (version) do nothing;
