-- The standard migration runner wraps this file in one transaction.
-- Called as the first statement of the same transaction as every admitted write
-- or account deletion. VOLATILE reads the current owner after a lock wait.
create or replace function public.lyb_native_account_admit(
  p_subject text, p_owner uuid
) returns void language plpgsql volatile as $$
declare
  actual_owner uuid;
begin
  if p_subject is null or btrim(p_subject) = '' or p_owner is null then
    raise exception 'account_changed' using errcode = 'LYB01';
  end if;
  select id into actual_owner from public.app_users
    where identity_provider = 'jovie' and identity_subject = p_subject
    for update;
  if actual_owner is distinct from p_owner then
    raise exception 'account_changed' using errcode = 'LYB01';
  end if;
end;
$$;

insert into public.schema_migrations(version) values ('20261010120000_native_account_admission')
  on conflict do nothing;
