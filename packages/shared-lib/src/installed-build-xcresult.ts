/**
 * Diff an xcresulttool test export against launch manifest paths.
 * A trace counts only when a passing non-fixture test recorded it inside the bundle.
 */

export const INSTALLED_TRACE_PREFIX = 'lyb-installed-trace';
export const INSTALLED_BUILD_ID_PREFIX = 'lyb-installed-build-id';

export type TraceKind = 'native-interaction' | 'service';

export type EvidenceReason =
  'missing-trace' | 'fixture-substitute' | 'installed-build-id-absent' | 'missing-xcresult';

export interface EvidenceFailure {
  reason: EvidenceReason;
  pathId?: string;
  kind?: TraceKind;
}

export interface XcresultNode {
  nodeType?: string;
  name?: string;
  nodeIdentifier?: string;
  result?: string;
  suggestedHumanReadableName?: string;
  children?: XcresultNode[];
}

/** `xcrun xcresulttool get test-results tests --path <bundle>` plus the bundle hash. */
export interface XcresultBundleExport {
  sha256: string;
  tests: {
    testNodes?: XcresultNode[];
    testPlanConfigurations?: { configurationName?: string }[];
  };
}

const TRACE_KINDS: readonly TraceKind[] = ['native-interaction', 'service'];
const TRACE = new RegExp(`^${INSTALLED_TRACE_PREFIX}\\|([^|]+)\\|(native-interaction|service)$`);
const BUILD_ID = new RegExp(`^${INSTALLED_BUILD_ID_PREFIX}\\|([0-9a-f]{40})$`);
const TEST_ID = /^[\w.]+\/test\w+\(\)$/;
const FIXTURE_LABEL = /fixture|synthetic|override|bypass|-lybuitest/i;

interface Frame {
  testId: string | null;
  result: string | null;
  fixture: boolean;
}

interface ObservedTrace {
  pathId: string;
  kind: TraceKind;
  testId: string | null;
  result: string | null;
  fixture: boolean;
}

function labels(node: XcresultNode): string[] {
  return [node.name, node.nodeIdentifier, node.suggestedHumanReadableName].filter(
    (label): label is string => typeof label === 'string' && label.length > 0,
  );
}

function isFixtureLabel(label: string): boolean {
  if (BUILD_ID.test(label) || TRACE.test(label)) return false;
  return FIXTURE_LABEL.test(label);
}

function isKind(value: string): value is TraceKind {
  return value === 'native-interaction' || value === 'service';
}

function targetMatches(testId: string | null, kind: TraceKind): boolean {
  if (!testId || !TEST_ID.test(testId)) return false;
  const ui = testId.includes('UITests/');
  if (kind === 'native-interaction') return ui;
  return testId.includes('Tests/') && !ui;
}

function walk(
  nodes: readonly XcresultNode[],
  frame: Frame,
  onTrace: (trace: ObservedTrace) => void,
  onBuildId: (id: string) => void,
): void {
  for (const node of nodes) {
    const ownLabels = labels(node);
    const ownFixture = ownLabels.some((label) => isFixtureLabel(label));
    const next: Frame =
      node.nodeType === 'Test Case'
        ? {
            testId: typeof node.nodeIdentifier === 'string' ? node.nodeIdentifier : null,
            result: typeof node.result === 'string' ? node.result : null,
            fixture: frame.fixture || ownFixture,
          }
        : ownFixture
          ? { ...frame, fixture: true }
          : frame;
    for (const label of ownLabels) {
      const buildId = BUILD_ID.exec(label);
      if (buildId && next.testId && next.result === 'Passed' && !next.fixture) {
        onBuildId(buildId[1]);
      }
      const trace = TRACE.exec(label);
      const kind = trace?.[2];
      if (trace?.[1] && kind && isKind(kind)) {
        onTrace({
          pathId: trace[1],
          kind,
          testId: next.testId,
          result: next.result,
          fixture: next.fixture || isFixtureLabel(label),
        });
      }
    }
    if (node.children?.length) walk(node.children, next, onTrace, onBuildId);
  }
}

function dedupe(failures: EvidenceFailure[]): EvidenceFailure[] {
  const seen = new Set<string>();
  const unique: EvidenceFailure[] = [];
  for (const failure of failures) {
    const key = `${failure.reason}|${failure.pathId ?? ''}|${failure.kind ?? ''}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(failure);
  }
  return unique;
}

export function checkInstalledBuildXcresult(
  pathIds: readonly string[],
  bundles: readonly XcresultBundleExport[],
): EvidenceFailure[] {
  const failures: EvidenceFailure[] = [];
  const required = [...new Set(pathIds)];
  if (required.length === 0 || required.some((id) => id.length === 0)) {
    failures.push({ reason: 'missing-trace' });
  }
  if (bundles.length === 0) failures.push({ reason: 'missing-xcresult' });

  const buildIds = new Set<string>();
  const satisfied = new Map<string, Set<TraceKind>>();
  for (const bundle of bundles) {
    if (!/^[a-f0-9]{64}$/.test(bundle.sha256)) {
      failures.push({ reason: 'missing-xcresult' });
      continue;
    }
    const configurationFixture = (bundle.tests.testPlanConfigurations ?? []).some((item) =>
      isFixtureLabel(item.configurationName ?? ''),
    );
    walk(
      bundle.tests.testNodes ?? [],
      { testId: null, result: null, fixture: configurationFixture },
      (trace) => {
        if (trace.fixture) {
          failures.push({
            reason: 'fixture-substitute',
            pathId: trace.pathId,
            kind: trace.kind,
          });
          return;
        }
        if (trace.result !== 'Passed' || !targetMatches(trace.testId, trace.kind)) return;
        const kinds = satisfied.get(trace.pathId) ?? new Set<TraceKind>();
        kinds.add(trace.kind);
        satisfied.set(trace.pathId, kinds);
      },
      (id) => buildIds.add(id),
    );
  }

  if (buildIds.size !== 1) failures.push({ reason: 'installed-build-id-absent' });
  for (const pathId of required) {
    if (!pathId) continue;
    const kinds = satisfied.get(pathId) ?? new Set<TraceKind>();
    for (const kind of TRACE_KINDS) {
      if (!kinds.has(kind)) failures.push({ reason: 'missing-trace', pathId, kind });
    }
  }
  return dedupe(failures);
}
