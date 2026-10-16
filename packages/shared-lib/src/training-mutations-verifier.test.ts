import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url)).replace(/\/$/, '');
const production = root + '/apps/web/db/tests/verify-training-mutations.py';
const safetyFunctions = ['isolated_environment', 'run_command', 'verify_postgres_tools'];
// trace's CLI can swallow SystemExit; preserve the actual unittest result.
const driver = `
import ast, json, pathlib, runpy, sys, trace
tracer = trace.Trace(count=True, trace=False, ignoredirs=[sys.prefix])
test_path, coverage_dir, production = sys.argv[1:]
sys.argv = [test_path]
status = 0
try:
    tracer.runctx("runpy.run_path(test_path, run_name='__main__')",
                  {"runpy": runpy, "test_path": test_path}, {})
except SystemExit as error:
    status = error.code
finally:
    results = tracer.results()
    results.write_results(show_missing=True, summary=True, coverdir=coverage_dir)
    path = pathlib.Path(production).resolve()
    safety = {}
    for node in ast.parse(path.read_text()).body:
        if isinstance(node, ast.FunctionDef) and node.name in (
                "isolated_environment", "run_command", "verify_postgres_tools"):
            statements = {item.lineno for item in ast.walk(node)
                          if isinstance(item, ast.stmt) and item is not node
                          and not (isinstance(item, ast.Expr)
                                   and isinstance(item.value, ast.Constant)
                                   and isinstance(item.value.value, str))}
            executed = {line for (file, line), count in results.counts.items()
                        if pathlib.Path(file).resolve() == path and count > 0}
            safety[node.name] = {"executedStatements": len(statements & executed),
                                 "statements": len(statements)}
    print("Training verifier safety execution: " + json.dumps(safety), flush=True)
sys.exit(status)
`;

function checkedTrace(test: string, coverage: string) {
  const output = execFileSync('python3', ['-c', driver, test, coverage, production], {
    encoding: 'utf8',
    cwd: root,
    timeout: 30_000,
  });
  expect(output).toContain('Training verifier behavior tests executed: 7');
  const row = output
    .split('\n')
    .find((line) => line.startsWith('Training verifier safety execution: '));
  expect(row, 'Actual production safety function execution must be reported').toBeDefined();
  const safety = JSON.parse(row!.replace('Training verifier safety execution: ', '')) as Record<
    string,
    { executedStatements: number; statements: number }
  >;
  expect(Object.keys(safety).sort()).toEqual([...safetyFunctions].sort());
  for (const name of safetyFunctions) {
    expect(safety[name].statements, name).toBeGreaterThan(0);
    expect(safety[name].executedStatements, name).toBe(safety[name].statements);
  }
  return output;
}

it('executes actual training verifier safety and failure contracts', () => {
  const coverage = mkdtempSync(tmpdir() + '/lyb-training-verifier-coverage-');
  try {
    const output = checkedTrace(
      root + '/apps/web/db/tests/test_verify_training_mutations.py',
      coverage,
    );
    console.log(
      output
        .split('\n')
        .filter((line) =>
          /verify-training-mutations|behavior tests executed|safety execution/.test(line),
        )
        .join('\n'),
    );
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);

it('rejects actual Python assertion failures and nonzero exits', () => {
  const directory = mkdtempSync(tmpdir() + '/lyb-training-verifier-failure-');
  try {
    const test = directory + '/failed.py';
    writeFileSync(
      test,
      'import unittest\nclass Failure(unittest.TestCase):\n    def test_real_failure(self):\n        self.assertEqual(1, 2)\nunittest.main()\n',
    );
    expect(() => checkedTrace(test, directory)).toThrow(/AssertionError: 1 != 2/);
    writeFileSync(test, 'import sys; sys.exit(7)\n');
    expect(() => checkedTrace(test, directory)).toThrow(/Command failed/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

it('rejects import-only production coverage despite a passing suite marker', () => {
  const directory = mkdtempSync(tmpdir() + '/lyb-training-verifier-unexecuted-');
  try {
    const test = directory + '/loaded.py';
    writeFileSync(
      test,
      'import runpy\nrunpy.run_path(' +
        JSON.stringify(production) +
        ')\nprint("Training verifier behavior tests executed: 7")\n',
    );
    expect(() => checkedTrace(test, directory)).toThrow(/isolated_environment/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
