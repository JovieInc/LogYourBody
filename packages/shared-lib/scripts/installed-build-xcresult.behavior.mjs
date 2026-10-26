import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createContext, SourceTextModule, SyntheticModule } from 'node:vm';
import { readFile } from 'node:fs/promises';
import {
  LAUNCH_CONTRACT,
  LAUNCH_CONTRACT_DIGEST,
} from '../../../scripts/fixtures/lyb-certification/lyb-launch-contract.mjs';
import { emitLaunchManifest } from '../../../scripts/lyb-launch-manifest.mjs';
import { checkInstalledBuildXcresult } from '../src/installed-build-xcresult.ts';

// Checker controls only. These exports are not installed-build, TestFlight, or product proof.
const BUILD = 'a'.repeat(40);
const FAILURE_STATES = [
  'denial',
  'no-data',
  'offline',
  'stale',
  'conflicting',
  'unsafe-date',
  'impossible-date',
  'expired-date',
  'maintenance',
];
const root = fileURLToPath(new URL('../../..', import.meta.url));
const cli = fileURLToPath(new URL('./installed-build-xcresult.mjs', import.meta.url));
const oracleURL = new URL(
  '../../../scripts/fixtures/lyb-certification/lyb-native-certification.mjs',
  import.meta.url,
);
const contractModule =
  await import('../../../scripts/fixtures/lyb-certification/lyb-launch-contract.mjs');

const context = createContext({ process: { argv: [] } });
const oracle = new SourceTextModule(readFileSync(oracleURL, 'utf8'), {
  context,
  initializeImportMeta: (meta) => {
    meta.url = oracleURL.href;
  },
});
await oracle.link((specifier) => {
  const exports =
    specifier === 'node:fs/promises'
      ? { readFile }
      : specifier === './lyb-launch-contract.mjs'
        ? contractModule
        : specifier === '../packages/release-channel-contracts/dogfood-exposure.ts'
          ? {
              evaluateExposureEvidence: () => {
                throw new Error('Exposure requires the real Jovie oracle');
              },
            }
          : null;
  assert.ok(exports, `Unexpected oracle dependency: ${specifier}`);
  return new SyntheticModule(
    Object.keys(exports),
    function () {
      for (const [key, value] of Object.entries(exports)) this.setExport(key, value);
    },
    { context },
  );
});
await oracle.evaluate();
const { certifyNativeReceipt } = oracle.namespace;

function token(value) {
  return value
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}

function bindings() {
  return Object.fromEntries(
    LAUNCH_CONTRACT.requiredPaths.map((path) => [
      path.id,
      ['native-interaction', 'service'].map((kind) => {
        const suffix = kind === 'native-interaction' ? 'Interaction' : 'Service';
        const suite =
          kind === 'native-interaction' ? 'InstalledInteractionTests' : 'InstalledServiceTests';
        return `${suite}/test${token(path.id)}${suffix}()`;
      }),
    ]),
  );
}

function installedExport(manifest) {
  const traces = [];
  for (const path of manifest.paths) {
    path.testIds.forEach((testId, index) => {
      const kind = index === 0 ? 'native-interaction' : 'service';
      traces.push({
        pathId: path.id,
        kind,
        testId,
        result: 'Passed',
        activity: `installed-build ${kind} ${path.id}`,
        installedBuildId: BUILD,
        origin: 'installed-build',
      });
    });
  }
  for (const route of manifest.routes) {
    for (const state of route.states) {
      for (const kind of ['native-interaction', 'service']) {
        const suffix = kind === 'native-interaction' ? 'Interaction' : 'Service';
        traces.push({
          pathId: state.pathIds[0],
          surface: route.surface,
          stateId: state.id,
          kind,
          testId: `InstalledStateTests/test${token(route.surface)}${token(state.id)}${suffix}()`,
          result: 'Passed',
          activity: `installed-build ${kind} ${route.surface} ${state.id}`,
          installedBuildId: BUILD,
          origin: 'installed-build',
        });
      }
    }
  }
  return {
    schema: 'lyb-installed-build-xcresult/v1',
    sha256: 'c'.repeat(64),
    installedBuildId: BUILD,
    source: { repository: 'JovieInc/LogYourBody', gitSha: BUILD, mergedSha: BUILD },
    build: { bundleId: 'com.logyourbody.app', version: '1.2.0', buildNumber: '120' },
    toolchain: { xcodeVersion: '26.0', swiftVersion: '6.2' },
    device: { name: 'iPhone 16', osVersion: '26.2' },
    fixture: { sha256: 'b'.repeat(64), seed: 289 },
    configuration: { name: 'Release', flags: [] },
    traces,
    captures: [...new Set(manifest.paths.flatMap((path) => path.requiredCaptures))].map((name) => ({
      name,
      sha256: 'd'.repeat(64),
    })),
    recoveredAfterRetry: false,
    infrastructureSkip: false,
  };
}

function check(xcresult, manifest = emitLaunchManifest(bindings())) {
  return {
    manifest,
    result: checkInstalledBuildXcresult({ manifest, contract: LAUNCH_CONTRACT, xcresult }),
  };
}

test('a complete installed-build export is a receipt the pinned oracle accepts', () => {
  const manifest = emitLaunchManifest(bindings());
  assert.equal(manifest.launchContract.digest, LAUNCH_CONTRACT_DIGEST);
  const { result } = check(installedExport(manifest), manifest);
  assert.deepEqual(result.reasons, []);
  assert.equal(result.ok, true);
  const certified = certifyNativeReceipt(manifest, result.receipt);
  assert.equal(certified.verdict, 'PASS', certified.reasons.join(', '));
  assert.equal(certified.schema, 'lyb-native-certification/v2');
});

test('a manifest path without an xcresult entry fails the check', () => {
  const manifest = emitLaunchManifest(bindings());
  const xcresult = installedExport(manifest);
  xcresult.traces = xcresult.traces.filter(
    (trace) =>
      !(trace.pathId === 'launch.timeline' && trace.kind === 'native-interaction') &&
      !(trace.pathId === 'launch.stats' && trace.kind === 'service'),
  );
  const { result } = check(xcresult, manifest);
  assert.equal(result.ok, false);
  assert.equal(result.receipt, null);
  assert.ok(result.reasons.includes('missing-xcresult-entry:launch.timeline:native-interaction'));
  assert.ok(result.reasons.includes('missing-xcresult-entry:launch.stats:service'));
  console.log(
    'missing-xcresult-entry:launch.timeline:native-interaction\nmissing-xcresult-entry:launch.stats:service',
  );
});

test('a fixture substitute trace fails the check', () => {
  const manifest = emitLaunchManifest(bindings());
  const xcresult = installedExport(manifest);
  xcresult.traces.push({
    pathId: 'launch.timeline',
    kind: 'native-interaction',
    testId: 'LogYourBodyUITests/testFixtureSubstituteTimeline()',
    result: 'Passed',
    activity: '-lybUITestPhotoTimelineHUDFixture',
    installedBuildId: BUILD,
    origin: 'installed-build',
  });
  const { result } = check(xcresult, manifest);
  assert.equal(result.ok, false);
  assert.equal(result.receipt, null);
  assert.ok(
    result.reasons.includes(
      'fixture-substitute:LogYourBodyUITests/testFixtureSubstituteTimeline()',
    ),
  );
  console.log('fixture-substitute:LogYourBodyUITests/testFixtureSubstituteTimeline()');
});

test('an absent installed build id fails the check', () => {
  const manifest = emitLaunchManifest(bindings());
  const xcresult = installedExport(manifest);
  delete xcresult.installedBuildId;
  for (const trace of xcresult.traces) delete trace.installedBuildId;
  const { result } = check(xcresult, manifest);
  assert.equal(result.ok, false);
  assert.equal(result.receipt, null);
  assert.ok(result.reasons.includes('installed-build-id-absent'));
  console.log('installed-build-id-absent');
});

test('the not_verified placeholder is an absent installed build id', () => {
  const manifest = emitLaunchManifest(bindings());
  const xcresult = installedExport(manifest);
  xcresult.installedBuildId = 'not_verified';
  for (const trace of xcresult.traces) trace.installedBuildId = 'not_verified';
  const { result } = check(xcresult, manifest);
  assert.equal(result.ok, false);
  assert.ok(result.reasons.includes('installed-build-id-absent'));
  console.log('installed-build-id-absent');
});

test('denial, no-data, offline, stale, conflicting, unsafe, impossible, expired, and maintenance need both traces', () => {
  const manifest = emitLaunchManifest(bindings());
  const xcresult = installedExport(manifest);
  xcresult.traces = xcresult.traces.filter((trace) => !FAILURE_STATES.includes(trace.stateId));
  const { result } = check(xcresult, manifest);
  assert.equal(result.ok, false);
  assert.equal(result.receipt, null);
  for (const surface of LAUNCH_CONTRACT.primarySurfaces) {
    for (const stateId of FAILURE_STATES) {
      for (const kind of ['native-interaction', 'service']) {
        assert.ok(
          result.reasons.includes(`missing-xcresult-entry:${surface}:${stateId}:${kind}`),
          `${surface} ${stateId} ${kind}`,
        );
      }
    }
  }
  console.log(FAILURE_STATES.map((stateId) => `missing-xcresult-entry:${stateId}`).join('\n'));
});

test('the CLI fails closed for a missing entry, a fixture substitute, and an absent build id', () => {
  const manifest = emitLaunchManifest(bindings());
  const directory = mkdtempSync(join(tmpdir(), 'lyb-xcresult-'));
  const manifestPath = join(directory, 'manifest.json');
  const contractPath = join(directory, 'contract.json');
  const xcresultPath = join(directory, 'xcresult.json');
  writeFileSync(manifestPath, JSON.stringify(manifest));
  writeFileSync(contractPath, JSON.stringify(LAUNCH_CONTRACT));
  const run = (xcresult) => {
    writeFileSync(xcresultPath, JSON.stringify(xcresult));
    return spawnSync(
      process.execPath,
      ['--experimental-strip-types', cli, manifestPath, contractPath, xcresultPath],
      { encoding: 'utf8', cwd: root },
    );
  };
  try {
    const passed = run(installedExport(manifest));
    assert.equal(passed.status, 0, passed.stderr);
    assert.equal(JSON.parse(passed.stdout).schema, 'lyb-native-certification/v2');

    const missing = installedExport(manifest);
    missing.traces = missing.traces.filter(
      (trace) => !(trace.pathId === 'launch.directive' && trace.kind === 'native-interaction'),
    );
    const missingRun = run(missing);
    assert.equal(missingRun.status, 1);
    assert.match(missingRun.stderr, /missing-xcresult-entry:launch\.directive:native-interaction/);
    console.log('missing-xcresult-entry:launch.directive:native-interaction');

    const fixture = installedExport(manifest);
    fixture.configuration.flags = ['-lybUITestTrainingFixture'];
    const fixtureRun = run(fixture);
    assert.equal(fixtureRun.status, 1);
    assert.match(fixtureRun.stderr, /fixture-substitute:configuration/);
    console.log('fixture-substitute:configuration');

    const absent = installedExport(manifest);
    absent.installedBuildId = '';
    const absentRun = run(absent);
    assert.equal(absentRun.status, 1);
    assert.match(absentRun.stderr, /installed-build-id-absent/);
    console.log('installed-build-id-absent');

    const usage = spawnSync(process.execPath, ['--experimental-strip-types', cli], {
      encoding: 'utf8',
    });
    assert.equal(usage.status, 2);
    assert.match(usage.stderr, /usage:/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
