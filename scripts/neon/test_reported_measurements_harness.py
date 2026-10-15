#!/usr/bin/env python3
"""Process/discovery contracts; real JSONB assertions run separately on PostgreSQL16."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('test-reported-measurements.py')
spec = importlib.util.spec_from_file_location('reported_harness', SCRIPT)
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class HarnessContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='lyb-reported-contract-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'commands.jsonl'
        for name in ('initdb', 'pg_ctl', 'psql'):
            self.tool(name)

    def tool(self, name, major=16, failure='', count=22):
        body = f'''#!{sys.executable}
import os,sys,json
from pathlib import Path
if '--version' in sys.argv:
 print('{name} (PostgreSQL) {major}.15');sys.exit(0)
assert not any(key.startswith('PG') or key=='DATABASE_URL' for key in os.environ)
with Path({str(self.log)!r}).open('a') as out: out.write(json.dumps(sys.argv)+'\\n')
if sys.argv[0].endswith('initdb'):
 Path(sys.argv[sys.argv.index('-D')+1]).mkdir()
if sys.argv[0].endswith('pg_ctl'):
 cluster=Path(sys.argv[sys.argv.index('-D')+1]);pid=cluster/'postmaster.pid'
 if sys.argv[-1]=='start': pid.write_text('fixture')
 if sys.argv[-1]=='stop':
  if {failure!r}=='stop': print('injected stop failure');sys.exit(42)
  pid.unlink()
if sys.argv[0].endswith('psql'):
 sql=sys.stdin.read() if '-c' not in sys.argv and '-f' not in sys.argv else ''
 if 'PREPARE write_record' in sql:
  if {failure!r}=='sql': print('injected SQL failure');sys.exit(42)
  print('DO\\n'*{count},end='')
'''
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o700)
        return path

    def cli(self, trace=False):
        command = [sys.executable]
        if trace:
            command += ['-m', 'trace', '--count', '--summary', '--coverdir', str(self.root/'coverage')]
        command += [str(SCRIPT), '--run', '--postgres-bin', str(self.bin)]
        return subprocess.run(command, env={**os.environ, 'DATABASE_URL':'synthetic-rejected',
            'PGHOST':'remote-rejected', 'PGSERVICEFILE':'synthetic-rejected'},
            capture_output=True, text=True, timeout=15)

    def test_no_database_without_explicit_opt_in(self):
        result = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn('no database is contacted by default', result.stderr)
        self.assertFalse(self.log.exists())

    def test_extracts_only_actual_generic_upsert_and_all_fail_closed_assertions(self):
        sql = harness.regression_sql()
        self.assertEqual(sql.count('PREPARE write_record'), 1)
        self.assertEqual(sql.count('DO $$ BEGIN IF ('), 22)
        self.assertEqual(sql.count('IS NOT TRUE THEN RAISE EXCEPTION'), 22)
        self.assertEqual(sql.count('EXECUTE write_record('), 31)
        self.assertIn('legacy omission erased reported measurements', sql)
        self.assertIn('legacy same-reading replay erased known zero presence', sql)

    def test_ambiguous_extraction_refuses_before_cluster_creation(self):
        adapter = self.root / 'adapter.ts'
        adapter.write_text(harness.ADAPTER.read_text()*2)
        with patch.object(harness, 'ADAPTER', adapter), patch.object(harness.tempfile, 'mkdtemp') as cluster:
            with patch.object(sys, 'argv', [str(SCRIPT), '--run', '--postgres-bin', str(self.bin)]):
                with self.assertRaisesRegex(RuntimeError, 'Expected one actual native-records upsert'):
                    harness.main()
            cluster.assert_not_called()

    def test_missing_nonexecutable_and_mixed_tools_fail_before_cluster(self):
        environment = {'PATH':os.defpath,'LC_ALL':'C'}
        for name in ('initdb','pg_ctl','psql'):
            with self.subTest(name=name):
                self.tool(name,major=18)
                with self.assertRaisesRegex(RuntimeError,'PostgreSQL16 required for '+name):
                    harness.verify_postgres_tools(self.bin,environment)
                self.tool(name).chmod(0o600)
                with self.assertRaisesRegex(RuntimeError,'Missing executable.*'+name):
                    harness.verify_postgres_tools(self.bin,environment)
                self.tool(name).unlink()
                with self.assertRaisesRegex(RuntimeError,'Missing executable.*'+name):
                    harness.verify_postgres_tools(self.bin,environment)
                self.tool(name)
        with patch.object(harness.shutil,'which',return_value=None):
            with self.assertRaisesRegex(RuntimeError,'Missing executable'):
                harness.verify_postgres_tools(None,environment)

    def test_real_process_failure_survives_trace_and_cleans_only_owned_cluster(self):
        self.tool('psql',failure='sql')
        result=self.cli(trace=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('injected SQL failure',result.stdout)
        commands=[json.loads(line) for line in self.log.read_text().splitlines()]
        start=next(row for row in commands if row[-1]=='start')
        self.assertIn("-h ''",start[start.index('-o')+1])
        owned=Path(start[start.index('-D')+1]).parent
        self.assertEqual(commands[-1][-1],'stop')
        self.assertFalse(owned.exists())
        self.assertIn('-X',next(row for row in commands if row[0].endswith('psql')))

    def test_success_counts_actual_do_results_and_rejects_incomplete_execution(self):
        result=self.cli()
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('"sqlChecks": 22, "writes": 31',result.stdout)
        import contextlib,io
        output=io.StringIO()
        with contextlib.redirect_stdout(output), patch.object(sys,'argv',[str(SCRIPT),'--run','--postgres-bin',str(self.bin)]):
            harness.main()
        self.assertIn('"sqlChecks": 22, "writes": 31',output.getvalue())
        self.tool('psql',count=21)
        result=self.cli(trace=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('executed 21',result.stderr)

    def test_failed_stop_retains_task_owned_cluster_and_fails(self):
        self.tool('pg_ctl',failure='stop')
        result=self.cli()
        self.assertNotEqual(result.returncode,0)
        commands=[json.loads(line) for line in self.log.read_text().splitlines()]
        owned=Path(commands[0][commands[0].index('-D')+1]).parent
        self.assertTrue((owned/'data/postmaster.pid').exists())
        self.assertIn('Could not stop task-owned cluster; retained',result.stdout)
        # Fixture tools never started a server; remove only this synthetic directory.
        import shutil
        shutil.rmtree(owned)

    def test_command_timeouts_are_bounded_and_propagate(self):
        with patch.object(harness.subprocess,'run',side_effect=subprocess.TimeoutExpired('tool',10)) as run:
            with self.assertRaises(subprocess.TimeoutExpired):
                harness.verify_postgres_tools(self.bin,{'PATH':os.defpath})
            self.assertEqual(run.call_args.kwargs['timeout'],10)
        original=harness.subprocess.run
        def timeout_sql(command,**kwargs):
            if command[0].endswith('psql') and kwargs.get('input',''):
                self.assertEqual(kwargs['timeout'],60)
                raise subprocess.TimeoutExpired('psql',60)
            return original(command,**kwargs)
        with patch.object(harness.subprocess,'run',side_effect=timeout_sql):
            with patch.object(sys,'argv',[str(SCRIPT),'--run','--postgres-bin',str(self.bin)]):
                with self.assertRaises(subprocess.TimeoutExpired):harness.main()
        commands=[json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(commands[-1][-1],'stop')


if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(HarnessContracts))
    print(f'Reported measurements harness behavior tests executed: {result.testsRun}',flush=True)
    raise SystemExit(not result.wasSuccessful())
