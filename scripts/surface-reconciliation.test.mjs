import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  BASELINE_PATH,
  INVENTORY_PATH,
  REPO_ROOT,
  assess,
  enumerateSurfaces,
  findingsFor,
  formatReport,
  loadInventory,
} from './surface-reconciliation.mjs';

const script = join(REPO_ROOT, 'scripts', 'surface-reconciliation.mjs');
const launchDigest = '697ae849faa806850bbfcb54b3977b00797f6d0bf9b86ccf6b57d6d2c0bbe0d7';

function writeTree(root, files) {
  for (const [path, content] of Object.entries(files)) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, content);
  }
}

function fixtureInventory(surfaces) {
  return `${JSON.stringify({ schema: 'lyb-launch-contract/v1', surfaces }, null, 2)}\n`;
}

function redTree() {
  return {
    'apps/ios/LogYourBody/DesignSystem/Theme.swift': `enum WorldClassScreen: String {
    case home
    case email
}
`,
    'apps/ios/LogYourBody/Views/HomeView.swift': 'view.worldClassScreen(.home)\n',
    'apps/ios/LogYourBody/Views/EmailView.swift': 'view.worldClassScreen(.email)\n',
    'apps/web/src/app/page.tsx': 'export default function Page() { return <main>Home</main>; }\n',
    'apps/web/src/app/gone/page.tsx': `import { redirect } from 'next/navigation';
export default function Gone() { redirect('/'); }
`,
    'apps/web/src/app/extra/page.tsx': 'export default function Extra() { return <main>Extra</main>; }\n',
  };
}

const redInventory = {
  'ios.screen.home': 'launch',
  'ios.screen.email': 'hide',
  'web:/': 'launch',
  'web:/gone': 'delete',
};

test('the vendored launch contract matches the Jovie fixture digest', () => {
  const bytes = readFileSync(INVENTORY_PATH);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), launchDigest);
  assert.equal(loadInventory(INVENTORY_PATH).digest, launchDigest);
});

test('a fixture tree fails on one unlisted surface and one reachable hidden surface', () => {
  const root = mkdtempSync(join(tmpdir(), 'surface-red-'));
  try {
    writeTree(root, redTree());
    const inventoryPath = join(root, 'inventory.json');
    writeFileSync(inventoryPath, fixtureInventory(redInventory));
    const result = execFileSync(
      process.execPath,
      [script, '--root', root, '--inventory', inventoryPath, '--no-baseline'],
      { encoding: 'utf8' },
    );
    assert.fail(`expected failure, got\n${result}`);
  } catch (error) {
    if (!error.status) throw error;
    assert.equal(error.status, 1);
    const output = `${error.stdout}`;
    assert.match(output, /surface reconciliation: fail/);
    assert.match(output, /web:\/extra/);
    assert.match(output, /apps\/web\/src\/app\/extra\/page\.tsx/);
    assert.match(output, /ios\.screen\.email/);
    assert.match(output, /apps\/ios\/LogYourBody\/Views\/EmailView\.swift/);
    assert.match(output, /hidden-reachable\s+hide/);
    assert.doesNotMatch(output, /web:\/gone/);
    assert.doesNotMatch(output, /ios\.screen\.home/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('redirect tombstones and unmounted hide or delete surfaces stay quiet', () => {
  const root = mkdtempSync(join(tmpdir(), 'surface-clean-'));
  try {
    const files = redTree();
    delete files['apps/web/src/app/extra/page.tsx'];
    delete files['apps/ios/LogYourBody/Views/EmailView.swift'];
    files['apps/ios/LogYourBody/Views/MainTabViewPolicies.swift'] = `enum PaidAppSurface: Equatable {
    case weightLoggerMVP
    case photoTimelineHUD
}
enum Policy {
    static func surface() -> PaidAppSurface { .photoTimelineHUD }
}
`;
    files['apps/ios/LogYourBody/Views/MainTabView.swift'] = `#if DEBUG
selectedSurface = .weightLoggerMVP
#endif
switch selected {
case .weightLoggerMVP:
    Logger()
case .photoTimelineHUD:
    Timeline()
}
`;
    files['apps/ios/LogYourBody/Views/SecretScreen.swift'] = 'struct SecretScreen<Content: View>: View {}\n';
    writeTree(root, files);
    const { inventory } = loadInventory(
      writeInventory(root, {
        ...redInventory,
        'ios.mode.weightLoggerMVP': 'delete',
        'ios.mode.photoTimelineHUD': 'launch',
        'ios.screen.chooseHomeView': 'delete',
      }),
    );
    // chooseHomeView is absent from this enum; the delete tombstone is not a route.
    const findings = findingsFor(enumerateSurfaces(root), inventory);
    assert.deepEqual(findings, []);
    const reported = assess({ findings, baseline: null });
    assert.equal(reported.ok, true);
    assert.match(formatReport(reported.summary, reported.rows), /\(no drift\)/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

function writeInventory(root, surfaces) {
  const path = join(root, 'inventory.json');
  writeFileSync(path, fixtureInventory(surfaces));
  return path;
}

test('an unlisted native screen reports the registry path', () => {
  const root = mkdtempSync(join(tmpdir(), 'surface-native-'));
  try {
    writeTree(root, {
      'apps/ios/LogYourBody/DesignSystem/Theme.swift': `enum WorldClassScreen: String {
    case home
    case secret
}
`,
      'apps/ios/LogYourBody/Views/Canvas.swift': 'struct MesocycleCanvasScreen: View {}\n',
    });
    const { inventory } = loadInventory(
      writeInventory(root, { 'ios.screen.home': 'launch' }),
    );
    const findings = findingsFor(enumerateSurfaces(root), inventory);
    assert.deepEqual(
      findings.map((finding) => [finding.kind, finding.id, finding.path]),
      [
        ['unlisted', 'ios.screen.secret', 'apps/ios/LogYourBody/DesignSystem/Theme.swift'],
        ['unlisted', 'ios.view.MesocycleCanvasScreen', 'apps/ios/LogYourBody/Views/Canvas.swift'],
      ],
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('editing the baseline cannot silence a new surface against the merge base', () => {
  const root = mkdtempSync(join(tmpdir(), 'surface-base-'));
  const git = (args) =>
    execFileSync('git', args, {
      cwd: root,
      encoding: 'utf8',
      env: {
        ...process.env,
        GIT_AUTHOR_NAME: 'Surface Test',
        GIT_AUTHOR_EMAIL: 'surface@example.com',
        GIT_COMMITTER_NAME: 'Surface Test',
        GIT_COMMITTER_EMAIL: 'surface@example.com',
      },
    });
  try {
    writeTree(root, {
      'apps/web/src/app/page.tsx': 'export default function Page() { return <main>Home</main>; }\n',
      'scripts/fixtures/lyb-launch-contract.json': fixtureInventory({ 'web:/': 'launch' }),
      'scripts/fixtures/surface-reconciliation-baseline.json': baselineFile(
        fixtureInventory({ 'web:/': 'launch' }),
        [],
      ),
    });
    git(['init', '-b', 'main']);
    git(['add', '.']);
    git(['-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-m', 'base']);
    const base = git(['rev-parse', 'HEAD']).trim();
    writeTree(root, {
      'apps/web/src/app/extra/page.tsx':
        'export default function Extra() { return <main>Extra</main>; }\n',
    });
    const extra = {
      kind: 'unlisted',
      disposition: null,
      id: 'web:/extra',
      path: 'apps/web/src/app/extra/page.tsx',
    };
    writeFileSync(
      join(root, 'scripts/fixtures/surface-reconciliation-baseline.json'),
      baselineFile(fixtureInventory({ 'web:/': 'launch' }), [extra]),
    );
    let output = '';
    try {
      execFileSync(
        process.execPath,
        [
          script,
          '--root',
          root,
          '--inventory',
          join(root, 'scripts/fixtures/lyb-launch-contract.json'),
          '--baseline',
          join(root, 'scripts/fixtures/surface-reconciliation-baseline.json'),
          '--base-ref',
          base,
        ],
        { encoding: 'utf8' },
      );
      assert.fail('new surface was silenced');
    } catch (error) {
      assert.equal(error.status, 1);
      output = `${error.stdout}`;
    }
    assert.match(output, /FAIL/);
    assert.match(output, /web:\/extra/);
    assert.match(output, /apps\/web\/src\/app\/extra\/page\.tsx/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('shrinking a resolved finding passes and a stale baseline row does not', () => {
  const kept = {
    kind: 'hidden-reachable',
    disposition: 'hide',
    id: 'ios.screen.email',
    path: 'apps/ios/LogYourBody/Views/EmailView.swift',
  };
  const gone = {
    kind: 'unlisted',
    disposition: null,
    id: 'web:/extra',
    path: 'apps/web/src/app/extra/page.tsx',
  };
  const shrunk = assess({ findings: [kept], baseline: [kept], baseFindings: [kept, gone] });
  assert.equal(shrunk.ok, true);
  const stale = assess({ findings: [kept], baseline: [kept, gone], baseFindings: [kept, gone] });
  assert.equal(stale.ok, false);
  assert.equal(stale.rows.find((row) => row.id === 'web:/extra').result, 'resolved');
});

test('the repository matches its baseline and keeps deleted modes off launch routes', () => {
  const { inventory, digest } = loadInventory(INVENTORY_PATH);
  const started = Date.now();
  const findings = findingsFor(enumerateSurfaces(REPO_ROOT), inventory);
  assert.ok(Date.now() - started < 60000);
  const baseline = JSON.parse(readFileSync(BASELINE_PATH, 'utf8'));
  assert.equal(baseline.inventoryDigest, digest);
  assert.deepEqual(findings, baseline.findings);
  const ids = new Set(findings.map((finding) => finding.id));
  assert.equal(ids.has('web:/training/canvas'), true);
  assert.equal(ids.has('ios.screen.email'), true);
  assert.equal(ids.has('ios.sheet.trainingLiveSession'), true);
  assert.equal(ids.has('ios.mode.weightLoggerMVP'), false);
  assert.equal(ids.has('ios.mode.legacyFullDashboardBeta'), false);
  assert.equal(ids.has('ios.screen.chooseHomeView'), false);
  assert.equal(ids.has('web:/landing'), false);
  assert.equal(ids.has('web:/mobile'), false);
  assert.equal(ids.has('ios.screen.home'), false);
  const output = execFileSync(process.execPath, [script], { cwd: REPO_ROOT, encoding: 'utf8' });
  assert.match(output, /surface reconciliation: pass/);
  assert.match(output, /web:\/training\/canvas/);
  assert.match(output, /apps\/web\/src\/app\/training\/canvas\/page\.tsx/);
  assert.match(output, /ios\.screen\.email/);
});

function baselineFile(inventoryText, findings) {
  return `${JSON.stringify(
    {
      schema: 'lyb.surface-reconciliation-baseline/v1',
      inventoryDigest: createHash('sha256').update(inventoryText).digest('hex'),
      findings,
    },
    null,
    2,
  )}\n`;
}
