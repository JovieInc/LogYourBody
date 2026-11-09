import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

// The trace CLI swallows SystemExit. Keep coverage while propagating suite failures.
const driver = `
import runpy, sys, trace
test_path, coverage_dir = sys.argv[1:]
sys.argv = [test_path]
tracer = trace.Trace(count=True, trace=False, ignoredirs=[sys.prefix])
status = 0
try:
    tracer.runctx("runpy.run_path(test_path, run_name='__main__')",
                  {"runpy": runpy, "test_path": test_path}, {})
except SystemExit as error:
    status = error.code
finally:
    tracer.results().write_results(show_missing=True, summary=True, coverdir=coverage_dir)
sys.exit(status)
`;

function checkedTrace(test: string, coverage: string, root: string) {
  return execFileSync('python3', ['-c', driver, test, coverage], {
    encoding: 'utf8',
    cwd: root,
    timeout: 90_000,
  });
}

it('invalidates native source guards for every app and native test source and build policy', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const sources = execFileSync(
    'git',
    [
      'ls-files',
      '-z',
      '--',
      'apps/ios/LogYourBody',
      'apps/ios/LogYourBodyTests',
      'apps/ios/LogYourBodyUITests',
    ],
    { cwd: root, encoding: 'utf8' },
  )
    .split('\0')
    .filter((path) => path.endsWith('.swift'));
  const plan = JSON.parse(
    execFileSync(
      'pnpm',
      ['exec', 'turbo', 'run', 'test', '--filter=@logyourbody/shared-lib', '--dry=json'],
      { cwd: root, encoding: 'utf8', timeout: 20_000, maxBuffer: 8 * 1024 * 1024 },
    ),
  );
  const task = plan.tasks.find(
    (item: { taskId: string }) => item.taskId === '@logyourbody/shared-lib#test',
  );
  expect(sources.length).toBeGreaterThan(0);
  expect(task).toBeDefined();
  const guardedInputs = [
    ...sources,
    'apps/ios/.swiftlint.yml',
    'apps/ios/LogYourBody.xcodeproj/project.pbxproj',
    'apps/ios/LogYourBody/Info.plist',
    'apps/ios/LogYourBody/LogYourBody.entitlements',
  ];
  const missing = guardedInputs.filter((path) => !Object.hasOwn(task.inputs, `../../${path}`));
  expect(
    missing.slice(0, 5),
    `${missing.length} native guard inputs missing from Turbo inputs`,
  ).toEqual([]);
}, 30_000);

it('keeps replay and onboarding state fixtures free of UIKit and SwiftUI animation waits in DEBUG only', () => {
  const source = readFileSync(
    new URL('../../../apps/ios/LogYourBody/LogYourBodyApp.swift', import.meta.url),
    'utf8',
  );
  const debugBlocks = [...source.matchAll(/^[ \t]*#if DEBUG\n(.*?)^[ \t]*#endif/gms)]
    .map((match) => match[1])
    .join('\n');
  const policy = debugBlocks.match(
    /static func usesDeterministicUITestAnimations\(arguments: \[String\]\) -> Bool \{(.*?)\n {4}\}/s,
  )?.[1];
  expect(policy, 'a single DEBUG policy must cover both state fixtures').toBeDefined();
  for (const flag of ['-lybUITestChatReplayFixture', '-lybUITestBodyScoreOnboardingFixture']) {
    expect(policy).toContain(`arguments.contains("${flag}")`);
  }
  const condition = String.raw`if Self\.usesDeterministicUITestAnimations\(arguments: ProcessInfo\.processInfo\.arguments\) \{`;
  expect(debugBlocks).toMatch(
    new RegExp(`${condition}\\s*UIView\\.setAnimationsEnabled\\(false\\)`),
  );
  expect(debugBlocks).toMatch(
    new RegExp(
      `${condition}\\s*transaction\\.animation = nil\\s*transaction\\.disablesAnimations = true`,
    ),
  );
  expect(source.replace(/^[ \t]*#if DEBUG\n.*?^[ \t]*#endif/gms, '')).not.toContain(
    'usesDeterministicUITestAnimations',
  );
});

it('keeps XCTest methods independent so each receives its own execution budget', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const paths = execFileSync('git', ['ls-files', 'apps/ios/LogYourBodyUITests'], {
    cwd: root,
    encoding: 'utf8',
  })
    .trim()
    .split('\n')
    .filter((path) => path.endsWith('.swift'));
  const calls = /(?<!\bfunc\s+)\b(?:self\.)?(test[A-Z]\w*)\s*\(/g;
  expect('func testExample() throws { assertRecovery() }'.match(calls)).toBeNull();
  expect('func testExample() throws { try self.testNested() }'.match(calls)).toEqual([
    'self.testNested(',
  ]);
  const nested = paths.flatMap((path) =>
    [...readFileSync(`${root}/${path}`, 'utf8').matchAll(calls)].map(
      (match) => `${path}: ${match[1]}`,
    ),
  );
  expect(nested, 'Select separate XCTest cases instead of calling tests from tests').toEqual([]);
});

it('selects every dated recovery state and journey as independent native evidence', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const native = readFileSync(
    `${root}/apps/ios/LogYourBodyUITests/LogYourBodyUITests+DatedTimeline.swift`,
    'utf8',
  );
  const audit = readFileSync(`${root}/scripts/ios/launch-quality-audit.sh`, 'utf8');
  const selectors = audit.split('LAUNCH_QUALITY_UI_TESTS=(')[1].split('\n)')[0];
  const journey = readFileSync(`${root}/apps/ios/LogYourBody/Services/LaunchJourney.swift`, 'utf8');
  const registry = journey.match(/enum RouteState[^{]*\{([^}]+)\}/)?.[1];
  expect(registry).toBeDefined();
  const states = [...registry!.matchAll(/case (\w+)(?: = "([\w-]+)")?/g)].map(
    (match) => match[2] ?? match[1],
  );
  const cases = [...native.matchAll(/func (testDated\w+)\(\) throws \{/g)];
  const recoveryCases = [
    ...native.matchAll(
      /func (testDatedStats\w+HasOneReachableRecovery)\(\) throws \{\s*assertDatedStatsRecovery\(state: "([\w-]+)"\)\s*\}/g,
    ),
  ];
  expect(recoveryCases.map((match) => match[2]).sort()).toEqual(states.sort());
  expect(cases.length).toBeGreaterThan(recoveryCases.length);
  for (const [, name] of cases) {
    expect(selectors.match(new RegExp(`"LogYourBodyUITests/${name}"`, 'g')), name).toHaveLength(1);
  }
});

it('pins shared offline UI fixtures before late network callbacks can replace their state', () => {
  const read = (path: string) =>
    readFileSync(new URL(`../../../apps/ios/LogYourBody/${path}`, import.meta.url), 'utf8');
  const app = read('LogYourBodyApp.swift');
  const manager = read('Services/RealtimeSyncManager.swift');
  const monitor = read('Services/RealtimeSyncManager+Part01.swift');
  const fixture = app.split('private func applyPaidMVPUITestFixtureIfNeeded()')[1];
  expect(fixture).toContain('realtimeSyncManager.applyOfflineUITestFixture()');
  expect(fixture).not.toContain('realtimeSyncManager.isOnline = false');
  expect(fixture).toContain('authManager.currentUser = User(');
  expect(fixture.indexOf('realtimeSyncManager.applyOfflineUITestFixture()')).toBeLessThan(
    fixture.indexOf('authManager.currentUser = User('),
  );
  const callback = monitor.split('networkMonitor.pathUpdateHandler =')[1]?.split('// MARK:')[0];
  expect(callback).toContain('self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)');
  expect(callback).not.toContain('self.isOnline =');
  expect(monitor.indexOf('networkMonitor.pathUpdateHandler =')).toBeLessThan(
    monitor.indexOf('networkMonitor.start(queue: queue)'),
  );
  const pin = manager.split('func applyOfflineUITestFixture()')[1]?.split('#endif')[0];
  expect(pin).toMatch(
    /usesOfflineUITestFixture = true[\s\S]*networkMonitor.cancel\(\)[\s\S]*isOnline = false\s*syncStatus = \.offline\s*pendingSyncCount = 0/,
  );
  const update = manager.split('func handleNetworkPathUpdate(isOnline: Bool)')[1];
  expect(update).toMatch(
    /#if DEBUG\s*guard !usesOfflineUITestFixture else \{ return \}\s*#endif\s*let wasOffline = !self.isOnline\s*self.isOnline = Self\.online\(isOnline\)/,
  );
  const release = manager.replace(/^[ \t]*#if DEBUG\n.*?^[ \t]*#endif/gms, '');
  expect(release).not.toMatch(/usesOfflineUITestFixture|applyOfflineUITestFixture/);
});

function barrierBody(source: string): string | undefined {
  const marker = 'final class Barrier';
  const start = source.indexOf(marker);
  if (start < 0) return undefined;
  const open = source.indexOf('{', start);
  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    else if (source[index] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, index);
    }
  }
  return undefined;
}

// A parked continuation resumes on one thread and on deinit.
export function shareExportBarrierFindings(source: string): string[] {
  const body = barrierBody(source);
  if (!body) return ['share-export barrier missing'];
  const findings: string[] = [];
  if (/withCheckedContinuation\s*\{\s*continuation\s*=/.test(body)) {
    findings.push('continuation is stored without a single-resume lock');
  }
  if (!body.includes('NSLock()')) findings.push('barrier has no lock');
  if (!body.includes('resumed')) findings.push('barrier can resume twice');
  if (!/deinit\s*\{\s*resume\(\)\s*\}/.test(body)) {
    findings.push('dropped barrier leaks its continuation');
  }
  if (/\bvar continuation:/.test(body) && !/private var continuation:/.test(body)) {
    findings.push('barrier publishes the continuation');
  }
  return findings;
}

it('resumes a parked share-export continuation once, including when the barrier is dropped', () => {
  const unsafe = `final class Barrier {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func resume() { continuation?.resume(); continuation = nil }
    }`;
  expect(shareExportBarrierFindings(unsafe)).toEqual([
    'continuation is stored without a single-resume lock',
    'barrier has no lock',
    'barrier can resume twice',
    'dropped barrier leaks its continuation',
    'barrier publishes the continuation',
  ]);
  const source = readFileSync(
    new URL('../../../apps/ios/LogYourBodyTests/BodyScoreShareExportTests.swift', import.meta.url),
    'utf8',
  );
  expect(shareExportBarrierFindings(source)).toEqual([]);
});

it('rejects incomplete XCTest proof through the launch gate validator with executed line coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const coverage = mkdtempSync(`${tmpdir()}/lyb-evidence-coverage-`);
  try {
    const output = checkedTrace(
      `${root}/scripts/ios/test_launch_quality_evidence.py`,
      coverage,
      root,
    );
    console.log(
      output
        .split('\n')
        .filter((line) => /launch-quality-evidence|behavior tests executed/.test(line))
        .join('\n'),
    );
    expect(output).toContain('Evidence validator behavior tests executed: 34');
    expect(output).toContain('launch-quality-evidence');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 90_000);

function terminateCleanupReceipt(body: string) {
  const directory = mkdtempSync(`${tmpdir()}/lyb-simctl-terminate-`);
  try {
    const script = `${directory}/cleanup.sh`;
    writeFileSync(
      script,
      `set -euo pipefail
run_with_timeout() {
  printf '%s\\n' "$1" >> "$RECEIPT/caps"
  printf '%s\\n' "$6" >> "$RECEIPT/bundles"
  return 124
}
xcrun() {
  printf '%s\\n' "$4" >> "$RECEIPT/raw"
}
${body}
cleanup_booted_simulator_apps
`,
    );
    execFileSync('/bin/bash', [script], {
      env: { PATH: '/usr/bin:/bin', RECEIPT: directory },
      encoding: 'utf8',
    });
    const lines = (name: string) => {
      try {
        return readFileSync(`${directory}/${name}`, 'utf8').trim().split('\n').filter(Boolean);
      } catch {
        return [];
      }
    };
    return { caps: lines('caps'), bundles: lines('bundles'), raw: lines('raw') };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

// A cold simctl terminate cannot consume the launch-quality step.
it('bounds cold simctl terminate so the launch-quality step can finish its last UI cases', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const source = readFileSync(`${root}/scripts/ios/launch-quality-audit.sh`, 'utf8');
  const start = source.indexOf('cleanup_booted_simulator_apps() {');
  const end = source.indexOf('\n}\n', start);
  const body = source.slice(start, end + 2);
  const unbounded = `cleanup_booted_simulator_apps() {
  xcrun simctl terminate booted com.logyourbody.app >/dev/null 2>&1 || true
  xcrun simctl terminate booted com.logyourbody.app.xctrunner >/dev/null 2>&1 || true
}`;
  const bundles = ['com.logyourbody.app', 'com.logyourbody.app.xctrunner'];
  expect(terminateCleanupReceipt(unbounded)).toEqual({ caps: [], bundles: [], raw: bundles });
  expect(terminateCleanupReceipt(body)).toEqual({ caps: ['20', '20'], bundles, raw: [] });
});

it('propagates evidence assertion failures and nonzero exits despite passing suite markers', () => {
  const directory = mkdtempSync(`${tmpdir()}/lyb-evidence-failure-`);
  try {
    const test = `${directory}/failed.py`;
    writeFileSync(
      test,
      'import sys, unittest\n' +
        'class Failure(unittest.TestCase):\n' +
        '    def test_missing_canvas_execution(self):\n' +
        '        self.assertEqual(0, 1)\n' +
        'result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Failure))\n' +
        'print("Evidence validator behavior tests executed: 32")\n' +
        'sys.exit(0 if result.wasSuccessful() else 1)\n',
    );
    expect(() => checkedTrace(test, directory, directory)).toThrow(/AssertionError: 0 != 1/);
    writeFileSync(test, 'import sys\nsys.exit(7)\n');
    expect(() => checkedTrace(test, directory, directory)).toThrow(/Command failed/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

it('runs the audit deadline regressions before native execution', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const output = execFileSync('python3', ['scripts/ios/test_xcodebuild_command_timeout.py'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 30_000,
  });
  expect(output).toContain('xcodebuild deadline behavior tests executed: 13');
}, 30_000);
