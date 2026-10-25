import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';
import { launchEvidencePathIds } from '../../../scripts/lyb-launch-manifest.mjs';
import {
  checkInstalledBuildXcresult,
  type TraceKind,
  type XcresultBundleExport,
  type XcresultNode,
} from './installed-build-xcresult';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const buildId = 'a'.repeat(40);

function method(pathId: string, kind: TraceKind): string {
  return `test${kind === 'native-interaction' ? 'Interaction' : 'Service'}${pathId.replace(/[^A-Za-z0-9]/g, 'X')}`;
}

function traceCase(pathId: string, kind: TraceKind, fixture = false): XcresultNode {
  const ui = kind === 'native-interaction';
  const name = method(pathId, kind);
  return {
    nodeType: 'Test Case',
    nodeIdentifier: `${fixture ? 'Fixture' : ''}${ui ? 'LaunchPathUITests' : 'LaunchPathServiceTests'}/${name}()`,
    name: `${name}()`,
    result: 'Passed',
    children: [
      {
        nodeType: 'Activity',
        name: `lyb-installed-trace|${pathId}|${kind}`,
      },
    ],
  };
}

function covered(
  pathIds: readonly string[],
  options?: { drop?: string; fixturePath?: string },
): XcresultBundleExport {
  const nodes: XcresultNode[] = [
    {
      nodeType: 'Test Case',
      nodeIdentifier: 'InstalledBuildIdentityTests/testRecordsInstalledBuildId()',
      name: 'testRecordsInstalledBuildId()',
      result: 'Passed',
      children: [{ nodeType: 'Activity', name: `lyb-installed-build-id|${buildId}` }],
    },
  ];
  for (const pathId of pathIds) {
    for (const kind of ['native-interaction', 'service'] as const) {
      if (options?.drop === `${pathId}:${kind}`) continue;
      nodes.push(traceCase(pathId, kind, options?.fixturePath === `${pathId}:${kind}`));
    }
  }
  return {
    sha256: 'b'.repeat(64),
    tests: { testNodes: nodes, testPlanConfigurations: [{ configurationName: 'Installed' }] },
  };
}

const paths = launchEvidencePathIds().all;

it('requires one native interaction and one service trace for every manifest and contract path', () => {
  expect(paths).toEqual(
    expect.arrayContaining([
      'launch.timeline',
      'launch.stats',
      'launch.directive',
      'ios.screen.photoTimeline:denial',
      'ios.screen.stats:no-data',
      'ios.screen.chat:offline',
      'ios.screen.photoTimeline:stale',
      'ios.screen.stats:conflicting',
      'ios.screen.chat:unsafe-date',
      'ios.screen.photoTimeline:impossible-date',
      'ios.screen.stats:expired-date',
      'ios.screen.chat:maintenance',
    ]),
  );
  expect(checkInstalledBuildXcresult(paths, [covered(paths)])).toEqual([]);
});

it('fails when a manifest path lacks an xcresult entry', () => {
  const failures = checkInstalledBuildXcresult(paths, [
    covered(paths, { drop: 'ios.screen.chat:offline:service' }),
  ]);
  expect(failures).toContainEqual({
    reason: 'missing-trace',
    pathId: 'ios.screen.chat:offline',
    kind: 'service',
  });
  expect(failures.some((failure) => failure.reason === 'fixture-substitute')).toBe(false);
});

it('fails when the trace is from a fixture substitute', () => {
  const failures = checkInstalledBuildXcresult(paths, [
    covered(paths, { fixturePath: 'launch.timeline:native-interaction' }),
  ]);
  expect(failures).toContainEqual({
    reason: 'fixture-substitute',
    pathId: 'launch.timeline',
    kind: 'native-interaction',
  });
  expect(failures).toContainEqual({
    reason: 'missing-trace',
    pathId: 'launch.timeline',
    kind: 'native-interaction',
  });
});

it('fails when the installed build id is absent', () => {
  const bundle = covered(paths);
  bundle.tests.testNodes = (bundle.tests.testNodes ?? []).filter(
    (node) => node.nodeIdentifier !== 'InstalledBuildIdentityTests/testRecordsInstalledBuildId()',
  );
  const failures = checkInstalledBuildXcresult(paths, [bundle]);
  expect(failures).toContainEqual({ reason: 'installed-build-id-absent' });
});

it('fails closed when the xcresult bundle cannot be read', () => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-xcresult-'));
  try {
    const bundle = join(directory, 'Empty.xcresult');
    mkdirSync(bundle);
    writeFileSync(join(bundle, 'Info.plist'), '<plist></plist>');
    const run = spawnSync(
      process.execPath,
      [
        '--experimental-strip-types',
        join(root, 'scripts/lyb-installed-xcresult-evidence.mjs'),
        '--xcresult',
        bundle,
      ],
      { encoding: 'utf8', cwd: root },
    );
    expect(run.status).toBe(1);
    const report = JSON.parse(run.stdout) as { ok: boolean; failures: { reason: string }[] };
    expect(report.ok).toBe(false);
    expect(report.failures).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ reason: 'missing-xcresult' }),
        expect.objectContaining({ reason: 'installed-build-id-absent' }),
        expect.objectContaining({ reason: 'missing-trace' }),
      ]),
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
