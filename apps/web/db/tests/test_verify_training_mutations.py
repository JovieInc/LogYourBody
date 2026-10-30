#!/usr/bin/env python3
"""Verifier process/safety contracts; actual SQL is exercised separately on PostgreSQL16."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('verify-training-mutations.py')
spec = importlib.util.spec_from_file_location('training_verifier', SCRIPT)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class VerifierContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='lyb-verifier-contract-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ('initdb', 'pg_ctl', 'psql'):
            self.tool(name)

    def tool(self, name, major=16, body=''):
        binary = self.bin / name
        binary.write_text(f'#!{sys.executable}\nimport os,sys\nfrom pathlib import Path\n'
                          f'if "--version" in sys.argv:\n print("{name} (PostgreSQL) {major}.15");sys.exit(0)\n' + body)
        binary.chmod(0o700)
        return binary

    def cleanup_fixture(self):
        web = self.root / 'web'
        adapter = web / 'src/lib/neon/user-directory-adapter.ts'
        adapter.parent.mkdir(parents=True)
        migrations = web / 'db/migrations'
        migrations.mkdir(parents=True)
        actual = SCRIPT.resolve().parents[2]
        adapter.write_text((actual / 'src/lib/neon/user-directory-adapter.ts').read_text())
        migration = migrations / '20261030120000_health_vault_grants.sql'
        migration.write_text((actual / 'db/migrations' / migration.name).read_text())
        return web, adapter, migration

    def test_cleanup_loads_future_tables_from_real_migrations_once(self):
        web, adapter, migration = self.cleanup_fixture()
        for path in (adapter, migration):
            path.write_text(path.read_text().replace('health_vault_grants', 'future_grants')
                            .replace('health_vault_consent_log', 'future_audit'))
        loaded = []
        tables = set()

        def sql(statement):
            table = re.search(r"public\.(\w+)'", statement)[1]
            return 't' if table in tables else 'f'

        def load(path):
            loaded.append(path)
            tables.update(re.findall(r'create table if not exists public\.(\w+)', path.read_text()))

        statements = verifier.account_cleanup_statements(web, sql, load)
        self.assertEqual(loaded, [migration])
        self.assertEqual(statements[7:9], [
            'delete from public.future_grants where user_subject = ${subject}',
            'delete from public.future_audit where user_subject = ${subject}',
        ])
        # A populated schema must not replay a migration over deliberate SQL mutants.
        verifier.account_cleanup_statements(web, lambda _: 't', load)
        self.assertEqual(loaded, [migration])

    def test_cleanup_preserves_required_order_and_identity_predicates(self):
        web, adapter, _ = self.cleanup_fixture()
        original = adapter.read_text()
        first = 'database`delete from public.chat_usage_limits where user_subject = ${subject}`,'
        for changed in [original.replace(first, ''),
                        original.replace('public.chat_usage_limits', 'public.chat_conversations', 1),
                        original.replace('lyb_delete_my_gyms(${subject})', 'lyb_delete_my_gyms(null)'),
                        original.replace("identity_provider = 'jovie'", "identity_provider = 'other'")]:
            with self.subTest(changed=changed):
                adapter.write_text(changed)
                with self.assertRaisesRegex(AssertionError, 'required account cleanup'):
                    verifier.account_cleanup_statements(web, lambda _: 't', lambda _: None)

    def test_cleanup_rejects_unsafe_or_duplicate_extensions(self):
        web, adapter, _ = self.cleanup_fixture()
        original = adapter.read_text()
        statement = 'delete from public.health_vault_grants where user_subject = ${subject}'
        for replacement in ['delete from public.health_vault_grants',
                            statement.replace('${subject}', "'other'"),
                            statement + ' or true',
                            statement + '` , database`' + statement]:
            with self.subTest(replacement=replacement):
                adapter.write_text(original.replace(statement, replacement))
                with self.assertRaisesRegex(AssertionError, 'subject-scoped cleanup|duplicate account cleanup'):
                    verifier.account_cleanup_statements(web, lambda _: 't', lambda _: None)

    def test_cleanup_requires_unique_canonical_migration(self):
        web, _, migration = self.cleanup_fixture()
        contents = migration.read_text()
        migration.unlink()
        with self.assertRaisesRegex(AssertionError, 'unique migration.*health_vault_grants'):
            verifier.account_cleanup_statements(web, lambda _: 'f', lambda _: None)
        migration.write_text(contents)
        migration.with_name('duplicate.sql').write_text(contents)
        with self.assertRaisesRegex(AssertionError, 'unique migration.*health_vault_grants'):
            verifier.account_cleanup_statements(web, lambda _: 'f', lambda _: None)

    def test_cleanup_fails_when_migration_does_not_create_table(self):
        web, _, _ = self.cleanup_fixture()
        with self.assertRaisesRegex(AssertionError, 'migration did not create.*health_vault_grants'):
            verifier.account_cleanup_statements(web, lambda _: 'f', lambda _: None)

    def test_connection_credentials_and_options_are_removed(self):
        env = verifier.isolated_environment({'DATABASE_URL': 'synthetic', 'PGHOST': 'remote',
            'PGPASSWORD': 'synthetic', 'PGSERVICEFILE': 'remote', 'PGOPTIONS': '-c unsafe',
            'PGCONNECT_TIMEOUT': '900', 'PATH': '/usr/bin'})
        self.assertEqual(env, {'PATH': '/usr/bin', 'PGCONNECT_TIMEOUT': '5'})

    def test_all_three_tools_must_report_postgres16(self):
        versions = verifier.verify_postgres_tools(self.bin, verifier.isolated_environment(os.environ))
        self.assertEqual(set(versions), {'initdb', 'pg_ctl', 'psql'})
        self.assertTrue(all('(PostgreSQL) 16.15' in version for version in versions.values()))

    def test_missing_or_nonexecutable_tool_fails_closed(self):
        for name in ('initdb', 'pg_ctl', 'psql'):
            with self.subTest(name=name):
                binary = self.bin / name
                binary.chmod(0o600)
                with self.assertRaisesRegex(RuntimeError, 'missing executable.*' + name):
                    verifier.verify_postgres_tools(self.bin, os.environ.copy())
                binary.chmod(0o700)
        (self.bin / 'initdb').unlink()
        with self.assertRaisesRegex(RuntimeError, 'missing executable.*initdb'):
            verifier.verify_postgres_tools(self.bin, os.environ.copy())

    def test_mixed_major_versions_fail_closed(self):
        for name in ('initdb', 'pg_ctl', 'psql'):
            with self.subTest(name=name):
                self.tool(name, major=18)
                with self.assertRaisesRegex(RuntimeError, 'PostgreSQL16 required for ' + name):
                    verifier.verify_postgres_tools(self.bin, os.environ.copy())
                self.tool(name)

    def test_real_command_failure_propagates(self):
        binary = self.tool('psql', body='print("injected SQL failure",file=sys.stderr)\nsys.exit(42)\n')
        with self.assertRaisesRegex(RuntimeError, 'injected SQL failure'):
            verifier.run_command([str(binary)], os.environ.copy())

    def test_commands_have_bounded_timeout(self):
        with patch.object(verifier.subprocess, 'run', side_effect=subprocess.TimeoutExpired('psql', 30)) as run:
            with self.assertRaises(subprocess.TimeoutExpired):
                verifier.run_command(['psql'], {'PATH': '/usr/bin'})
            self.assertEqual(run.call_args.kwargs['timeout'], 30)

    def test_cli_sql_failure_stops_private_cluster_and_removes_temp_files(self):
        log = self.root / 'commands.jsonl'
        body = ('with Path(os.environ["TEST_COMMAND_LOG"]).open("a") as out:\n'
                ' out.write(__import__("json").dumps(sys.argv)+"\\n")\n')
        self.tool('pg_ctl', body=body)
        self.tool('psql', body=body + 'print("injected SQL failure",file=sys.stderr)\nsys.exit(42)\n')
        env = dict(os.environ, TMPDIR=str(self.root), TEST_COMMAND_LOG=str(log),
                   DATABASE_URL='synthetic-rejected', PGHOST='remote-rejected')
        result = subprocess.run([sys.executable, str(SCRIPT), '--postgres-bin', str(self.bin)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('injected SQL failure', result.stderr)
        commands = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual(commands[0][-1], 'start')
        self.assertIn("listen_addresses=''", commands[0][commands[0].index('-o') + 1])
        self.assertIn('-h', commands[1])
        self.assertTrue(commands[1][commands[1].index('-h') + 1].startswith(str(self.root)))
        self.assertEqual(commands[-1][-1], 'stop')
        self.assertEqual(list(self.root.glob('lyb-mutation-pg-*')), [])


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(VerifierContracts))
    print(f'Training verifier behavior tests executed: {result.testsRun}', flush=True)
    raise SystemExit(not result.wasSuccessful())
