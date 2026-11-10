import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const vitest = fileURLToPath(new URL('../node_modules/vitest/vitest.mjs', import.meta.url));

it.each([
  {
    name: 'prepares cold Ruby before the unchanged release-health scenario deadline',
    startup: 6,
    scenario: 0,
    preflightExit: 0,
    status: 0,
  },
  {
    name: 'still rejects a release-health scenario exceeding five seconds',
    startup: 0,
    scenario: 6,
    preflightExit: 0,
    status: 1,
  },
  {
    name: 'refuses all release-health scenarios when runtime preparation fails',
    startup: 0,
    scenario: 0,
    preflightExit: 42,
    status: 1,
  },
])(
  '$name',
  ({ startup, scenario, preflightExit, status }) => {
    const directory = mkdtempSync(join(tmpdir(), 'lyb-release-health-startup-'));
    const ruby = execFileSync('which', ['ruby'], { encoding: 'utf8' }).trim();
    try {
      writeFileSync(
        join(directory, 'ruby'),
        `#!/bin/sh
if [ ! -e "$FIXTURE_STARTUP_LOG" ]; then
  sleep "$FIXTURE_STARTUP_DELAY"
else
  sleep "$FIXTURE_SCENARIO_DELAY"
fi
printf '%s\\n' "$*" >> "$FIXTURE_STARTUP_LOG"
case "$*" in
  *preflight*)
    if [ "$FIXTURE_PREFLIGHT_EXIT" != 0 ]; then
      echo 'fixture runtime preparation failed' >&2
      exit "$FIXTURE_PREFLIGHT_EXIT"
    fi
    ;;
esac
exec "$FIXTURE_REAL_RUBY" "$@"
`,
        { mode: 0o755 },
      );
      const result = spawnSync(
        process.execPath,
        [
          vitest,
          'run',
          'src/app-store-release-health.test.ts',
          '--testNamePattern=^App Store release health > blocks an approved breached build before requesting release$',
        ],
        {
          cwd: join(root, 'packages/shared-lib'),
          encoding: 'utf8',
          timeout: 20_000,
          env: {
            ...process.env,
            PATH: `${directory}${delimiter}${process.env.PATH}`,
            FIXTURE_REAL_RUBY: ruby,
            FIXTURE_STARTUP_LOG: join(directory, 'startup.log'),
            FIXTURE_STARTUP_DELAY: String(startup),
            FIXTURE_SCENARIO_DELAY: String(scenario),
            FIXTURE_PREFLIGHT_EXIT: String(preflightExit),
          },
        },
      );
      expect(result.error).toBeUndefined();
      expect(result.signal).toBeNull();
      expect(result.status, result.stdout + result.stderr).toBe(status);
      const calls = readFileSync(join(directory, 'startup.log'), 'utf8').trim().split('\n');
      expect(calls).toHaveLength(preflightExit ? 1 : 2);
      expect(calls[0]).toContain('"preflight"');
      if (preflightExit) {
        expect(result.stderr).toContain('fixture runtime preparation failed');
      } else {
        expect(calls[1]).toContain('"fixture":"breached"');
        if (scenario) expect(result.stderr).toContain('Test timed out in 5000ms');
        else expect(result.stdout).toMatch(/1 passed/);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  },
  25_000,
);
