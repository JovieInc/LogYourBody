-- Executed by the existing disposable PostgreSQL16 verifier, never a live DB.
begin;
create role lyb_gym_rls_test nologin;
grant usage on schema public to lyb_gym_rls_test;
grant select, insert, update, delete on public.gyms to lyb_gym_rls_test;
insert into public.app_users(id, identity_provider, identity_subject) values
  ('24800000-0000-4000-8000-000000000001', 'jovie', 'gym-rls-owner-a'),
  ('24800000-0000-4000-8000-000000000002', 'jovie', 'gym-rls-owner-b');
insert into public.gyms(id, owner_id, name, equipment, preferred_machines) values
  ('24800000-0000-4000-8000-000000000003', '24800000-0000-4000-8000-000000000001', 'Private A', '{}', '{}'),
  ('24800000-0000-4000-8000-000000000004', '24800000-0000-4000-8000-000000000002', 'Private B', '{dumbbells}', '{}');

set local role lyb_gym_rls_test;
do $$ begin
  if exists(select 1 from public.gyms) then raise exception 'Unscoped request read gyms'; end if;
end $$;
select set_config('lyb.gym_owner_id', '24800000-0000-4000-8000-000000000001', true);
do $$ declare affected integer; begin
  if (select count(*) from public.gyms) <> 1 then raise exception 'Owner isolation failed'; end if;
  if exists(select 1 from public.gyms where name = 'Private B') then raise exception 'Foreign gym readable'; end if;
  update public.gyms set name = 'Stolen' where id = '24800000-0000-4000-8000-000000000004';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Foreign gym update succeeded'; end if;
  delete from public.gyms where id = '24800000-0000-4000-8000-000000000004';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Foreign gym delete succeeded'; end if;
  begin
    insert into public.gyms(id,owner_id,name,equipment,preferred_machines) values
      ('24800000-0000-4000-8000-000000000005','24800000-0000-4000-8000-000000000002','Forged','{}','{}');
    raise exception 'Foreign gym insert succeeded';
  exception when insufficient_privilege then null; end;
  begin
    update public.gyms set owner_id = '24800000-0000-4000-8000-000000000002';
    raise exception 'Owner reassignment succeeded';
  exception when insufficient_privilege then null; end;
  update public.gyms set name = 'Edited A', equipment = '{cable,bench}'
    where id = '24800000-0000-4000-8000-000000000003';
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'Owned edit failed'; end if;
end $$;
select set_config('lyb.gym_owner_id', '24800000-0000-4000-8000-000000000002', true);
do $$ begin
  if (select array_agg(name) from public.gyms) is distinct from array['Private B'] then
    raise exception 'Second owner isolation failed';
  end if;
end $$;
reset role;
delete from public.app_users where id = '24800000-0000-4000-8000-000000000001';
do $$ begin
  if exists(select 1 from public.gyms where owner_id = '24800000-0000-4000-8000-000000000001') then
    raise exception 'Account deletion retained gym data';
  end if;
  if not exists(select 1 from public.gyms where name = 'Private B') then raise exception 'Account deletion crossed owners'; end if;
end $$;
rollback;
