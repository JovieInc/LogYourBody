#!/usr/bin/env python3
"""Apply the gym migration and RLS assertions in a disposable socket-only PostgreSQL16."""
import argparse
import getpass
import importlib.util
import os
from pathlib import Path
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--postgres-bin', type=Path, required=True)
    parser.add_argument('--migration', type=Path, help='Candidate for regression checks')
    args = parser.parse_args()
    tests = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location('mutation_checks', tests / 'verify-training-mutations.py')
    helpers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helpers)
    env = helpers.isolated_environment(os.environ)
    helpers.verify_postgres_tools(args.postgres_bin, env)
    run = lambda command: helpers.run_command(command, env)
    with tempfile.TemporaryDirectory(prefix='lyb-gym-pg-', dir='/tmp') as directory:
        root = Path(directory)
        data, socket = root / 'data', root / 'socket'
        socket.mkdir(mode=0o700)
        run([str(args.postgres_bin / 'initdb'), '-D', str(data), '-A', 'trust', '--no-locale', '-U', getpass.getuser()])
        control = [str(args.postgres_bin / 'pg_ctl'), '-D', str(data)]
        started = False
        try:
            run(control + ['-l', str(root / 'postgres.log'), '-o', f"-h '' -k {socket} -p 6549", '-w', 'start'])
            started = True
            client = [str(args.postgres_bin / 'psql'), '-X', '-q', '-h', str(socket), '-p', '6549',
                      '-U', getpass.getuser(), '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
            run(client + ['-c', 'create table public.schema_migrations(version text primary key)'])
            migrations = tests.parent / 'migrations'
            run(client + ['-f', str(migrations / '20260714183000_create_app_users.sql')])
            run(client + ['-f', str(args.migration or migrations / '20261025160000_gym_registry.sql')])
            run(client + ['-f', str(tests / 'gym-registry-rls.sql')])
            print('PASS: no-session, two-owner read/write RLS isolation, owned CRUD, account-delete cascade')
        except Exception:
            if (root / 'postgres.log').exists():
                print((root / 'postgres.log').read_text())
            raise
        finally:
            if started:
                run(control + ['-m', 'immediate', '-w', 'stop'])


if __name__ == '__main__':
    main()
