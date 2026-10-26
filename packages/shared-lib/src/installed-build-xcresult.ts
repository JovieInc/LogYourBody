// Diff an installed-build xcresult export against the launch route manifest
// and the JOV-6013 contract path list. A passing result is a receipt the
// pinned lyb-native-certification oracle can read. Synthetic exports used to
// test this function are not installed-build proof.

export const XCRESULT_SCHEMA = 'lyb-installed-build-xcresult/v1';
export const CERTIFICATION_SCHEMA = 'lyb-native-certification/v2';

export const TRACE_KINDS = ['native-interaction', 'service'] as const;
export type TraceKind = (typeof TRACE_KINDS)[number];

/** Route states the launch manifest must cover, including the parent journey's failure paths. */
export const REQUIRED_ROUTE_STATES = [
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
] as const;

const TIERS = new Set([
  'component_unit',
  'simulator_interaction',
  'service_integration',
  'physical_device',
]);
const TEST_ID = /^[\w.]+\/test\w+\(\)$/;
const SHA256 = /^[a-f0-9]{64}$/;
const BUILD_ID = /^[a-f0-9]{40}$/;
const FIXTURE_MARK = /fixture|override|bypass|-lybUITest/i;
const ABSENT_BUILD_IDS = new Set([
  '',
  '0',
  'absent',
  'missing',
  'unknown',
  'not_verified',
  'synthetic',
  'fixture',
  'undefined',
  'null',
]);

export interface XcresultTrace {
  pathId?: string;
  kind?: string;
  testId?: string;
  result?: string;
  activity?: string;
  installedBuildId?: string;
  surface?: string;
  stateId?: string;
  origin?: 'installed-build' | 'fixture-substitute';
}

export interface XcresultCapture {
  name?: string;
  sha256?: string;
}

export interface InstalledBuildXcresult {
  schema?: string;
  sha256?: string;
  installedBuildId?: string;
  source?: { repository?: string; gitSha?: string; mergedSha?: string };
  build?: { bundleId?: string; version?: string; buildNumber?: string };
  toolchain?: { xcodeVersion?: string; swiftVersion?: string };
  device?: { name?: string; osVersion?: string };
  fixture?: { sha256?: string; seed?: number };
  configuration?: { name?: string; flags?: string[] };
  traces?: XcresultTrace[];
  captures?: XcresultCapture[];
  recoveredAfterRetry?: boolean;
  infrastructureSkip?: boolean;
}

export interface ManifestPath {
  id?: string;
  tier?: string;
  testIds?: string[];
  requiredCaptures?: string[];
}

export interface LaunchManifest {
  schema?: string;
  launchContract?: { digest?: string };
  paths?: ManifestPath[];
  routes?: Array<{ surface?: string; states?: Array<{ id?: string; pathIds?: string[] }> }>;
}

export interface LaunchContractPaths {
  repository?: string;
  primarySurfaces?: string[];
  requiredPaths?: Array<{ id?: string }>;
}

export interface CertificationReceipt {
  schema: typeof CERTIFICATION_SCHEMA;
  launchContractDigest: string;
  source: { repository: string; gitSha: string; mergedSha: string };
  build: { bundleId: string; version: string; buildNumber: string; installedGitSha: string };
  toolchain: { xcodeVersion: string; swiftVersion: string };
  device: { name: string; osVersion: string };
  fixture: { sha256: string; seed: number };
  configuration: { name: string; flags: string[] };
  xcresult: { sha256: string };
  discoveredTestIds: string[];
  selectedTestIds: string[];
  records: Array<{ testId: string; result: 'Passed' }>;
  captures: Array<{ name: string; sha256: string }>;
  recoveredAfterRetry: false;
  infrastructureSkip: false;
}

export interface InstalledBuildCheck {
  ok: boolean;
  reasons: string[];
  receipt: CertificationReceipt | null;
}

function add(reasons: string[], reason: string): void {
  if (!reasons.includes(reason)) reasons.push(reason);
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function presentBuildId(value: unknown): value is string {
  return typeof value === 'string' && BUILD_ID.test(value) && !ABSENT_BUILD_IDS.has(value);
}

function isFixtureTrace(trace: XcresultTrace, flags: readonly string[]): boolean {
  if (trace.origin === 'fixture-substitute') return true;
  return [trace.testId, trace.activity, ...flags].some(
    (value) => typeof value === 'string' && FIXTURE_MARK.test(value),
  );
}

function covers(trace: XcresultTrace, flags: readonly string[], installedBuildId: string): boolean {
  return (
    trace.result === 'Passed' &&
    !isFixtureTrace(trace, flags) &&
    presentBuildId(trace.installedBuildId) &&
    trace.installedBuildId === installedBuildId &&
    typeof trace.testId === 'string' &&
    TEST_ID.test(trace.testId)
  );
}

/**
 * Fail closed unless every contract path and route state has a passed native
 * interaction and a passed service trace from the identified installed build.
 */
export function checkInstalledBuildXcresult(input: {
  manifest?: LaunchManifest | null;
  contract?: LaunchContractPaths | null;
  xcresult?: InstalledBuildXcresult | null;
}): InstalledBuildCheck {
  const reasons: string[] = [];
  const manifest = input.manifest ?? {};
  const contract = input.contract ?? {};
  const xcresult = input.xcresult ?? {};
  const traces = Array.isArray(xcresult.traces) ? xcresult.traces : [];
  const flags = Array.isArray(xcresult.configuration?.flags)
    ? xcresult.configuration.flags.filter((flag): flag is string => typeof flag === 'string')
    : null;
  const installedBuildId = presentBuildId(xcresult.installedBuildId)
    ? xcresult.installedBuildId
    : '';

  if (xcresult.schema !== XCRESULT_SCHEMA) add(reasons, 'xcresult-schema-mismatch');
  if (manifest.schema !== CERTIFICATION_SCHEMA) add(reasons, 'schema-mismatch');
  if (!SHA256.test(text(xcresult.sha256))) add(reasons, 'missing-xcresult');
  if (!installedBuildId) add(reasons, 'installed-build-id-absent');
  if (flags === null) add(reasons, 'missing-flags');
  else if (flags.some((flag) => FIXTURE_MARK.test(flag)))
    add(reasons, 'fixture-substitute:configuration');

  for (const trace of traces) {
    if (!trace || typeof trace !== 'object') continue;
    const identified = presentBuildId(trace.installedBuildId);
    if (!identified || (installedBuildId && trace.installedBuildId !== installedBuildId)) {
      add(reasons, identified ? 'installed-build-sha-mismatch' : 'installed-build-id-absent');
    }
    if (isFixtureTrace(trace, flags ?? [])) {
      add(reasons, `fixture-substitute:${text(trace.testId) || text(trace.pathId) || 'trace'}`);
    }
  }

  const scanFlags = flags ?? [];
  const paths = Array.isArray(manifest.paths) ? manifest.paths : [];
  const pathIds = new Set<string>();
  for (const required of contract.requiredPaths ?? []) {
    if (text(required?.id)) pathIds.add(required.id as string);
  }
  if (pathIds.size === 0) add(reasons, 'missing-xcresult-entry:contract');
  for (const path of paths) {
    if (text(path?.id)) pathIds.add(path.id as string);
  }

  for (const pathId of pathIds) {
    const path = paths.find((item) => item?.id === pathId);
    if (!path) {
      for (const kind of TRACE_KINDS) add(reasons, `missing-xcresult-entry:${pathId}:${kind}`);
      continue;
    }
    if (!TIERS.has(text(path.tier))) add(reasons, `unknown-tier:${pathId}`);
    if (!Array.isArray(path.testIds) || path.testIds.length === 0) {
      add(reasons, `path-without-tests:${pathId}`);
    }
    for (const kind of TRACE_KINDS) {
      const found = traces.some(
        (trace) =>
          trace.pathId === pathId &&
          trace.kind === kind &&
          covers(trace, scanFlags, installedBuildId),
      );
      if (!found) add(reasons, `missing-xcresult-entry:${pathId}:${kind}`);
    }
    for (const testId of path.testIds ?? []) {
      const found = traces.some(
        (trace) => trace.testId === testId && covers(trace, scanFlags, installedBuildId),
      );
      if (!found) add(reasons, `missing-xcresult-entry:${testId}`);
    }
  }

  const surfaces = Array.isArray(contract.primarySurfaces) ? contract.primarySurfaces : [];
  if (surfaces.length === 0) add(reasons, 'missing-xcresult-entry:primary-surfaces');
  const routes = Array.isArray(manifest.routes) ? manifest.routes : [];
  for (const surface of surfaces) {
    if (!text(surface)) continue;
    const route = routes.find((item) => item?.surface === surface);
    const declared = new Map(
      (route?.states ?? [])
        .filter((state) => text(state?.id))
        .map((state) => [state.id as string, state.pathIds ?? []]),
    );
    const stateIds = new Set<string>([...REQUIRED_ROUTE_STATES, ...declared.keys()]);
    for (const stateId of stateIds) {
      const statePaths = (declared.get(stateId) ?? []).filter((id) => text(id));
      for (const kind of TRACE_KINDS) {
        const found =
          statePaths.length > 0 &&
          traces.some(
            (trace) =>
              trace.surface === surface &&
              trace.stateId === stateId &&
              statePaths.includes(trace.pathId ?? '') &&
              trace.kind === kind &&
              covers(trace, scanFlags, installedBuildId),
          );
        if (!found) add(reasons, `missing-xcresult-entry:${surface}:${stateId}:${kind}`);
      }
    }
  }

  const digest = text(manifest.launchContract?.digest);
  if (!SHA256.test(digest)) add(reasons, 'launch-contract-digest-mismatch');
  const repository = text(contract.repository);
  const gitSha = text(xcresult.source?.gitSha);
  const mergedSha = text(xcresult.source?.mergedSha);
  if (!repository) add(reasons, 'launch-repository-mismatch');
  if (!gitSha) add(reasons, 'missing-source-sha');
  if (!mergedSha) add(reasons, 'missing-merged-sha');
  if (gitSha && mergedSha && gitSha !== mergedSha) add(reasons, 'run-sha-is-not-merged-sha');
  if (installedBuildId && mergedSha && installedBuildId !== mergedSha) {
    add(reasons, 'installed-build-sha-mismatch');
  }
  if (repository && text(xcresult.source?.repository) !== repository) {
    add(reasons, 'launch-repository-mismatch');
  }
  for (const [key, reason] of [
    ['bundleId', 'missing-bundleId'],
    ['version', 'missing-version'],
    ['buildNumber', 'missing-buildNumber'],
  ] as const) {
    if (!text(xcresult.build?.[key])) add(reasons, reason);
  }
  if (!text(xcresult.toolchain?.xcodeVersion)) add(reasons, 'missing-xcode-version');
  if (!text(xcresult.toolchain?.swiftVersion)) add(reasons, 'missing-swift-version');
  if (!text(xcresult.device?.name) || !text(xcresult.device?.osVersion)) {
    add(reasons, 'missing-device-identity');
  }
  const fixtureSeed = xcresult.fixture?.seed;
  if (!SHA256.test(text(xcresult.fixture?.sha256))) add(reasons, 'missing-fixture-hash');
  if (!Number.isInteger(fixtureSeed)) add(reasons, 'missing-seed');
  if (!text(xcresult.configuration?.name)) add(reasons, 'missing-configuration');
  if (xcresult.recoveredAfterRetry === true) add(reasons, 'flaky-only-success');
  if (xcresult.infrastructureSkip === true) add(reasons, 'infrastructure-skip');

  const captures = (Array.isArray(xcresult.captures) ? xcresult.captures : []).filter(
    (capture): capture is { name: string; sha256: string } =>
      text(capture?.name).length > 0 && SHA256.test(text(capture?.sha256)),
  );
  for (const path of paths) {
    for (const name of path.requiredCaptures ?? []) {
      if (!captures.some((capture) => capture.name === name)) {
        add(reasons, `missing-capture:${text(path.id)}:${name}`);
      }
    }
  }

  reasons.sort();
  if (
    reasons.length > 0 ||
    !installedBuildId ||
    flags === null ||
    typeof fixtureSeed !== 'number'
  ) {
    return { ok: false, reasons, receipt: null };
  }

  const records = [
    ...new Set(
      traces
        .filter((trace) => covers(trace, scanFlags, installedBuildId))
        .map((trace) => trace.testId as string),
    ),
  ].sort();
  const receipt: CertificationReceipt = {
    schema: CERTIFICATION_SCHEMA,
    launchContractDigest: digest,
    source: { repository, gitSha, mergedSha },
    build: {
      bundleId: text(xcresult.build?.bundleId),
      version: text(xcresult.build?.version),
      buildNumber: text(xcresult.build?.buildNumber),
      installedGitSha: installedBuildId,
    },
    toolchain: {
      xcodeVersion: text(xcresult.toolchain?.xcodeVersion),
      swiftVersion: text(xcresult.toolchain?.swiftVersion),
    },
    device: {
      name: text(xcresult.device?.name),
      osVersion: text(xcresult.device?.osVersion),
    },
    fixture: {
      sha256: text(xcresult.fixture?.sha256),
      seed: fixtureSeed,
    },
    configuration: { name: text(xcresult.configuration?.name), flags },
    xcresult: { sha256: text(xcresult.sha256) },
    discoveredTestIds: records,
    selectedTestIds: records,
    records: records.map((testId) => ({ testId, result: 'Passed' })),
    captures: captures.map((capture) => ({ name: capture.name, sha256: text(capture.sha256) })),
    recoveredAfterRetry: false,
    infrastructureSkip: false,
  };
  return { ok: true, reasons, receipt };
}
