#!/usr/bin/env python3
"""Prove gym row level security hides one subject's rows from another.

Disposable local Postgres only. The canonical migration is Neon, not Supabase.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

WEB = Path(__file__).resolve().parents[2]
MIGRATION = WEB / 'db' / 'migrations' / '20261025190000_gym_registry.sql'
USER_A = '11111111-1111-4111-8111-111111111111'
USER_B = '22222222-2222-4222-8222-222222222222'


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--postgres-bin', type=Path)
    args = parser.parse_args()
    bindir = args.postgres_bin
    initdb = str(bindir / 'initdb') if bindir else shutil.which('initdb')
    pg_ctl = str(bindir / 'pg_ctl') if bindir else shutil.which('pg_ctl')
    psql = str(bindir / 'psql') if bindir else shutil.which('psql')
    if not initdb or not pg_ctl or not psql:
        raise SystemExit('postgres binaries not found; pass --postgres-bin')

    with tempfile.TemporaryDirectory(prefix='lyb-gym-rls-') as temp:
        root = Path(temp)
        data = root / 'data'
        socket = root / 'socket'
        socket.mkdir(mode=0o700)
        run([initdb, '-D', str(data), '-U', 'lyb_gym_owner', '--auth-local=trust',
             '--auth-host=reject', '--no-locale', '--encoding=UTF8'])
        port = '55491'
        ctl = [pg_ctl, '-D', str(data)]
        run(ctl + ['-l', str(root / 'server.log'), '-o',
                   f"-h '' -k {socket} -p {port} -c shared_buffers=16MB -c max_connections=8 -c autovacuum=off",
                   '-w', 'start'])
        try:
            client = [psql, '-X', '-q', '-A', '-t', '-h', str(socket), '-p', port,
                      '-U', 'lyb_gym_owner', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']

            def sql(statement, check=True):
                result = subprocess.run(client, input=statement, text=True, capture_output=True, timeout=30)
                if check and result.returncode:
                    raise RuntimeError(result.stderr or result.stdout)
                return result

            def value(statement):
                lines = [line.strip() for line in sql(statement).stdout.splitlines() if line.strip()]
                if len(lines) != 1:
                    raise AssertionError(f'expected one value, got {lines!r} for {statement}')
                return lines[0]

            def as_user(subject, statement, check=True):
                return sql(f"""
begin;
set local role lyb_gym_app;
set local app.current_user_subject = {quote(subject)};
{statement}
commit;
""", check=check)

            def user_value(subject, statement):
                lines = [line.strip() for line in as_user(subject, statement).stdout.splitlines() if line.strip()]
                if len(lines) != 1:
                    raise AssertionError(f'expected one value, got {lines!r}')
                return lines[0]

            sql('create table if not exists public.schema_migrations (version text primary key);')
            sql(MIGRATION.read_text())
            flags = value(
                "select relrowsecurity::text || ',' || relforcerowsecurity::text "
                "from pg_class where oid = 'public.gyms'::regclass;"
            )
            assert flags == 'true,true', flags
            assert value(
                "select count(*) from information_schema.columns "
                "where table_schema = 'public' and table_name = 'gyms' "
                "and column_name in ('latitude', 'longitude', 'location', 'geom');"
            ) == '0'

            sql(f"""
create role lyb_gym_app nologin;
grant usage on schema public to lyb_gym_app;
grant select, insert, update, delete on public.gyms to lyb_gym_app;
grant execute on function public.lyb_list_gyms() to lyb_gym_app;
grant execute on function public.lyb_upsert_gym(uuid, text, text, text[], text[]) to lyb_gym_app;
grant execute on function public.lyb_delete_gym(uuid) to lyb_gym_app;
insert into public.gyms (id, user_subject, name, region, equipment, preferred_machines)
values
  ({quote(USER_A)}::uuid, 'user-a', 'North', 'north', array['dumbbells'], array['lat pulldown']),
  ({quote(USER_B)}::uuid, 'user-b', 'South', null, array['cable', 'machine'], '{{}}');
""")

            assert user_value('user-a', 'select count(*) from public.gyms;') == '1'
            assert user_value('user-a', 'select string_agg(name, \',\') from public.gyms;') == 'North'
            assert user_value('user-a', f'select count(*) from public.gyms where id = {quote(USER_B)}::uuid;') == '0'
            assert user_value('user-a', "select count(*) from public.gyms where user_subject = 'user-b';") == '0'
            assert user_value('user-b', 'select string_agg(name, \',\') from public.gyms;') == 'South'
            assert user_value('user-a', 'select string_agg(name, \',\') from public.lyb_list_gyms();') == 'North'
            hidden = value("""
begin;
set local role lyb_gym_app;
select count(*) from public.gyms;
commit;
""")
            assert hidden == '0', hidden

            stolen = as_user(
                'user-a',
                f"select name from public.lyb_upsert_gym({quote(USER_B)}::uuid, 'Stolen', null, array['dumbbells'], '{{}}');",
                check=False,
            )
            assert stolen.returncode != 0, stolen.stdout
            assert value(f'select name from public.gyms where id = {quote(USER_B)}::uuid;') == 'South'

            direct = as_user(
                'user-a',
                "insert into public.gyms (id, user_subject, name, equipment, preferred_machines) "
                "values ('33333333-3333-4333-8333-333333333333'::uuid, 'user-b', 'Stolen', '{}', '{}');",
                check=False,
            )
            assert direct.returncode != 0, direct.stdout
            assert 'row-level security' in (direct.stderr or '').lower() or 'gym_' in (direct.stderr or '')

            removed = as_user(
                'user-a',
                f'select id from public.lyb_delete_gym({quote(USER_B)}::uuid);',
                check=False,
            )
            assert removed.returncode != 0
            assert value(f"select count(*) from public.gyms where user_subject = 'user-b' and deleted_at is null;") == '1'

            denied = as_user('user-a', "select public.lyb_delete_my_gyms('user-b');", check=False)
            assert denied.returncode != 0
            sql("select public.lyb_delete_my_gyms('user-a');")
            assert value("select count(*) from public.gyms where user_subject = 'user-a';") == '0'
            assert value("select count(*) from public.gyms where user_subject = 'user-b';") == '1'
            print('PASS gym row level security hides another subject')
        finally:
            subprocess.run(ctl + ['-m', 'immediate', '-w', 'stop'], check=False, timeout=30)


def run(command):
    result = subprocess.run(command, text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result


if __name__ == '__main__':
    main()
