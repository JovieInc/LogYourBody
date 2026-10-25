-- Run against the real migration in a disposable database; rollback all fixtures/roles.
begin;
insert into public.app_users(id, identity_subject) values
  ('11111111-1111-4111-8111-111111111111', 'gym-owner-a'),
  ('22222222-2222-4222-8222-222222222222', 'gym-owner-b');
insert into public.gyms(id, owner_id, user_subject, payload) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'gym-owner-a',
   '{"name":"A","equipment":[],"preferredMachines":[]}'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'gym-owner-b',
   '{"name":"B","equipment":["barbell"],"preferredMachines":[]}');

create role gym_rls_test nologin nosuperuser nobypassrls;
grant usage on schema public to gym_rls_test;
grant select, insert, update, delete on public.gyms to gym_rls_test;
set local role gym_rls_test;
do $$ begin
  if (select count(*) from public.gyms) <> 0 then raise exception 'Unscoped read leaked gyms'; end if;
end $$;
select set_config('app.user_subject', 'gym-owner-a', true);
do $$
declare changed integer;
begin
  if (select count(*) from public.gyms) <> 1 then raise exception 'Owner A read isolation failed'; end if;
  if exists(select 1 from public.gyms where user_subject = 'gym-owner-b') then
    raise exception 'Owner A read owner B gym';
  end if;
  update public.gyms set payload = payload || '{"name":"Stolen"}' where user_subject = 'gym-owner-b';
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Cross-owner update succeeded'; end if;
  delete from public.gyms where user_subject = 'gym-owner-b';
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Cross-owner delete succeeded'; end if;
  begin
    insert into public.gyms(id,owner_id,user_subject,payload) values
      (gen_random_uuid(),'22222222-2222-4222-8222-222222222222','gym-owner-b',
       '{"name":"Forged","equipment":[],"preferredMachines":[]}');
    raise exception 'Cross-owner insert succeeded';
  exception when insufficient_privilege then null;
  end;
  update public.gyms set payload = payload || '{"name":"Confirmed"}' where user_subject = 'gym-owner-a';
  get diagnostics changed = row_count;
  if changed <> 1 then raise exception 'Owned CRUD unavailable'; end if;
end $$;
select set_config('app.user_subject', 'gym-owner-b', true);
do $$ begin
  if (select count(*) from public.gyms) <> 1 or
     exists(select 1 from public.gyms where user_subject = 'gym-owner-a') then
    raise exception 'Owner B read isolation failed';
  end if;
end $$;
reset role;
delete from public.app_users where identity_subject = 'gym-owner-a';
do $$ begin
  if exists(select 1 from public.gyms where user_subject = 'gym-owner-a') then
    raise exception 'Account deletion retained gyms';
  end if;
end $$;
rollback;
