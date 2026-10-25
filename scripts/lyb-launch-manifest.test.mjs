import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createContext, SourceTextModule, SyntheticModule } from 'node:vm';
import * as contract from './fixtures/lyb-certification/lyb-launch-contract.mjs';
import {
  emitLaunchManifest,
  launchEvidencePathIds,
  nativeSurfaces,
} from './lyb-launch-manifest.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const fixture = new URL('./fixtures/lyb-certification/', import.meta.url);
const oracleURL = new URL('lyb-native-certification.mjs', fixture);

// Run the byte-pinned oracle unchanged. Exposure is outside this manifest-only
// test; invoking it throws instead of substituting a passing certification.
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
        ? contract
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
const { certifyNativeReceipt, SCHEMA } = oracle.namespace;

// Synthetic identifiers and receipt used ONLY to exercise the oracle's schema.
// No selectors, records, captures, or installed-build evidence are emitted by this test.
const bindings = () =>
  Object.fromEntries(
    contract.LAUNCH_CONTRACT.requiredPaths.map((path, i) => [
      path.id,
      [`SyntheticSchemaTests/testPath${i}()`],
    ]),
  );
function schemaReceipt(manifest) {
  const testIds = manifest.paths.flatMap((path) => path.testIds);
  return {
    schema: SCHEMA,
    launchContractDigest: contract.LAUNCH_CONTRACT_DIGEST,
    source: {
      repository: 'JovieInc/LogYourBody',
      gitSha: 'a'.repeat(40),
      mergedSha: 'a'.repeat(40),
    },
    build: {
      bundleId: 'synthetic.schema.only',
      version: '0',
      buildNumber: '0',
      installedGitSha: 'a'.repeat(40),
    },
    toolchain: { xcodeVersion: 'synthetic', swiftVersion: 'synthetic' },
    device: { name: 'synthetic', osVersion: 'synthetic' },
    fixture: { sha256: 'b'.repeat(64), seed: 271 },
    configuration: { name: 'synthetic', flags: [] },
    xcresult: { sha256: 'c'.repeat(64) },
    discoveredTestIds: testIds,
    selectedTestIds: testIds,
    records: testIds.map((testId) => ({ testId, result: 'Passed' })),
    captures: manifest.paths
      .flatMap((path) => path.requiredCaptures)
      .map((name) => ({ name, sha256: 'd'.repeat(64) })),
  };
}

test('upstream schema and policy fixtures retain their exact source bytes', () => {
  const source = JSON.parse(readFileSync(new URL('source.json', fixture), 'utf8'));
  assert.equal(source.repository, 'JovieInc/Jovie');
  assert.equal(source.revision, '065ba6ff9c06ad2de13b2297fcf48bc5e8c43035');
  for (const [name, entry] of Object.entries(source.files)) {
    assert.equal(
      createHash('sha256')
        .update(readFileSync(new URL(name, fixture)))
        .digest('hex'),
      entry.sha256,
    );
  }
});

test('the emitted manifest validates against the unmodified Jovie main oracle fixture', () => {
  const manifest = emitLaunchManifest(bindings());
  assert.equal(manifest.schema, SCHEMA);
  const result = certifyNativeReceipt(manifest, schemaReceipt(manifest));
  assert.equal(result.verdict, 'PASS', result.reasons.join(', '));
  assert.equal(result.counts.declared, 13);
  assert.equal(manifest.observedNativeSurfaces.length, 49);
  assert.deepEqual(manifest.observedNativeSurfaces, nativeSurfaces());
  assert.deepEqual(manifest.launchContract.surfaces, contract.LAUNCH_CONTRACT.surfaces);
});

test('installed-build evidence ids list every contract path and route state', () => {
  const evidence = launchEvidencePathIds();
  assert.deepEqual(
    evidence.contractIds,
    contract.LAUNCH_CONTRACT.requiredPaths.map((path) => path.id),
  );
  assert.deepEqual(evidence.routeStateIds, [
    ...['ios.screen.photoTimeline', 'ios.screen.stats', 'ios.screen.chat'].flatMap((surface) =>
      [
        'ready',
        'denial',
        'no-data',
        'offline',
        'stale',
        'conflicting',
        'unsafe-date',
        'impossible-date',
        'expired-date',
        'maintenance',
      ].map((state) => `${surface}:${state}`),
    ),
  ]);
  assert.deepEqual(evidence.all, [...evidence.contractIds, ...evidence.routeStateIds]);
});

test('every primary route declares all LYB-183 launch states and binds known paths', () => {
  const manifest = emitLaunchManifest(bindings());
  assert.deepEqual(
    manifest.routes.map((route) => route.surface),
    ['ios.screen.photoTimeline', 'ios.screen.stats', 'ios.screen.chat'],
  );
  const pathIds = new Set(manifest.paths.map((path) => path.id));
  for (const route of manifest.routes) {
    assert.deepEqual(
      route.states.map((state) => state.id),
      [
        'ready',
        'denial',
        'no-data',
        'offline',
        'stale',
        'conflicting',
        'unsafe-date',
        'impossible-date',
        'expired-date',
        'maintenance',
      ],
    );
    for (const state of route.states) {
      assert.ok(state.pathIds.length);
      assert.ok(state.pathIds.every((id) => pathIds.has(id)));
    }
  }
});

function changedRegistry(path, change, assertion) {
  const temporary = mkdtempSync(join(tmpdir(), 'lyb-manifest-'));
  try {
    for (const name of [
      'apps/ios/LogYourBody/DesignSystem/Theme.swift',
      'apps/ios/LogYourBody/Views/MainTabViewPolicies.swift',
    ]) {
      const destination = join(temporary, name);
      mkdirSync(dirname(destination), { recursive: true });
      const source = readFileSync(join(root, name), 'utf8');
      writeFileSync(destination, name === path ? change(source) : source);
    }
    assertion(temporary);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

test('adding a native screen without a manifest entry fails closed', () => {
  for (const anchor of ['    case launch\n', '    var id: String { rawValue }\n']) {
    changedRegistry(
      'apps/ios/LogYourBody/DesignSystem/Theme.swift',
      (source) => source.replace(anchor, `${anchor}    case newLaunchScreen\n`),
      (temporary) =>
        assert.throws(
          () => emitLaunchManifest(bindings(), temporary),
          /Unclassified native surfaces: ios.screen.newLaunchScreen/,
        ),
    );
  }
});

test('adding a native app mode without a manifest entry also fails closed', () => {
  changedRegistry(
    'apps/ios/LogYourBody/Views/MainTabViewPolicies.swift',
    (source) =>
      source.replace(
        '    case weightLoggerMVP',
        '    case unapprovedMode\n    case weightLoggerMVP',
      ),
    (temporary) =>
      assert.throws(
        () => emitLaunchManifest(bindings(), temporary),
        /Unclassified native surfaces: ios.mode.unapprovedMode/,
      ),
  );
});

test('grouped and raw-valued cases cannot conceal an unclassified screen', () => {
  for (const declaration of [
    'case launch, newLaunchScreen',
    'case launch\n    case newScreen = "newLaunchScreen"',
  ]) {
    changedRegistry(
      'apps/ios/LogYourBody/DesignSystem/Theme.swift',
      (source) => source.replace('case launch\n', `${declaration}\n`),
      (temporary) =>
        assert.throws(
          () => emitLaunchManifest(bindings(), temporary),
          /ios.screen.newLaunchScreen/,
        ),
    );
  }
});

test('missing and unsupported native registries fail instead of producing an empty inventory', () => {
  for (const replacement of ['enum RenamedScreen:', 'enum WorldClassScreen:']) {
    changedRegistry(
      'apps/ios/LogYourBody/DesignSystem/Theme.swift',
      (source) =>
        replacement.includes('Renamed')
          ? source.replace('enum WorldClassScreen:', replacement)
          : source.replace('case launch\n', 'case launch(Int)\n'),
      (temporary) =>
        assert.throws(() => emitLaunchManifest(bindings(), temporary), /native registry/),
    );
  }
});

test('all 13 paths require explicit nonempty XCTest selectors; unknown bindings are rejected', () => {
  for (const path of contract.LAUNCH_CONTRACT.requiredPaths) {
    for (const value of [
      undefined,
      [],
      [''],
      ['PolicyTests/notATest()'],
      ['Tests/testA()', 'Tests/testA()'],
    ]) {
      assert.throws(
        () => emitLaunchManifest({ ...bindings(), [path.id]: value }),
        /XCTest bindings/,
      );
    }
  }
  assert.throws(
    () => emitLaunchManifest({ ...bindings(), 'launch.unrecognized': ['Tests/testA()'] }),
    /Unknown launch path/,
  );
  for (const value of [null, [], 'invalid'])
    assert.throws(() => emitLaunchManifest(value), /Expected path ID/);
});

test('oracle negative controls reject schema, policy, tier, capture, and surface drift', () => {
  const mutations = [
    [
      (manifest) => {
        manifest.schema = 'lyb-native-certification/v1';
      },
      'schema-mismatch',
    ],
    [
      (manifest) => {
        manifest.launchContract.digest = 'stale';
      },
      'launch-contract-digest-mismatch',
    ],
    [
      (manifest) => {
        manifest.paths[0].tier = 'component_unit';
      },
      'launch-path-tier:launch.baseline',
    ],
    [
      (manifest) => {
        manifest.paths[0].requiredCaptures = [];
      },
      'launch-path-capture:launch.baseline:baseline-manual',
    ],
    [
      (manifest) => {
        manifest.paths.pop();
      },
      'launch-path-count:launch.timeline',
    ],
    [
      (manifest) => {
        manifest.launchContract.surfaces['ios.screen.newLaunchScreen'] = 'launch';
      },
      'launch-unclassified-surface:ios.screen.newLaunchScreen',
    ],
  ];
  for (const [mutate, reason] of mutations) {
    const manifest = emitLaunchManifest(bindings());
    mutate(manifest);
    const result = certifyNativeReceipt(manifest, schemaReceipt(manifest));
    assert.equal(result.verdict, 'UNVERIFIED');
    assert.ok(result.reasons.includes(reason), result.reasons.join(', '));
  }
});

test('the manifest alone cannot certify a native build', () => {
  const result = certifyNativeReceipt(emitLaunchManifest(bindings()), {});
  assert.equal(result.verdict, 'UNVERIFIED');
  for (const reason of [
    'zero-test-run',
    'missing-xcresult',
    'missing-source-sha',
    'installed-build-not-identified',
  ]) {
    assert.ok(result.reasons.includes(reason));
  }
});

test('CLI emits deterministic JSON and exits nonzero without a partial manifest on invalid bindings', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'lyb-bindings-'));
  const script = fileURLToPath(new URL('./lyb-launch-manifest.mjs', import.meta.url));
  try {
    const path = join(temporary, 'bindings.json');
    writeFileSync(path, JSON.stringify(bindings()));
    const run = (...args) =>
      spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', cwd: temporary });
    const emitted = run(path);
    assert.ifError(emitted.error);
    assert.equal(emitted.status, 0, emitted.stderr);
    assert.equal(emitted.stdout, run(path).stdout);
    assert.deepEqual(JSON.parse(emitted.stdout), emitLaunchManifest(bindings()));
    for (const contents of ['{}', '{invalid json']) {
      writeFileSync(path, contents);
      const invalid = run(path);
      assert.equal(invalid.status, 1);
      assert.equal(invalid.stdout, '');
      assert.ok(invalid.stderr.length);
    }
    assert.equal(run().status, 1);
    assert.match(run().stderr, /usage:/);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});
