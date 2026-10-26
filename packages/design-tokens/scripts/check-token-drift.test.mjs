import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

const acceptedDrift = [
  {
    token: 'color.semantic.background',
    platform: 'ios',
    target: 'colors.background',
    canonical: '#000000',
    actual: '#333333',
  },
  {
    token: 'color.semantic.background',
    platform: 'web',
    target: '--background',
    canonical: '#000000',
    actual: '#333333',
  },
  {
    token: 'color.semantic.background',
    platform: 'web',
    target: 'tailwind:background',
    canonical: '#000000',
    actual: '#333333',
  },
  { token: 'spacing.md', platform: 'ios', target: 'spacing.md', canonical: 16, actual: 20 },
];

function fixture(t, options = {}) {
  const root = mkdtempSync(path.join(tmpdir(), 'lyb-token-drift-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));

  function write(relativePath, content) {
    const file = path.join(root, relativePath);
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, content);
    return file;
  }

  const script = write('packages/design-tokens/scripts/check-token-drift.mjs', '');
  copyFileSync(new URL('./check-token-drift.mjs', import.meta.url), script);
  write(
    'packages/design-tokens/tokens/fixture.json',
    JSON.stringify({
      color: { semantic: { background: { value: options.canonicalColor ?? '#000000' } } },
      spacing: { md: { value: options.canonicalSpacing ?? 16 } },
    }),
  );
  write(
    'apps/ios/LogYourBody/DesignSystem/Theme.swift',
    `
struct SpacingTheme {
    let md: CGFloat = ${options.iosSpacing ?? 20}
}
let colors = ColorTheme(
    background: Color(hex: "${options.iosColor ?? '#333333'}"),
    )
`,
  );
  write('apps/ios/LogYourBody/Extensions/Color+Theme.swift', '');
  write(
    'apps/web/tailwind.config.ts',
    `export default { colors: { 'background': '${options.tailwindColor ?? '#333333'}' } };`,
  );
  write(
    'apps/web/src/app/globals.css',
    `:root {
  --background: 0 0% ${options.cssLightness ?? 20}%;
  --added: 0 0% 40%;
}`,
  );
  const map = {
    'color.semantic.background': {
      ios: 'colors.background',
      web: ['--background', 'tailwind:background'],
    },
    'spacing.md': { ios: 'spacing.md' },
    ...options.map,
  };
  write('packages/design-tokens/token-map.json', JSON.stringify({ map }));
  const baseline = write(
    'packages/design-tokens/drift-baseline.json',
    `${JSON.stringify(
      {
        version: 1,
        drift: options.drift ?? acceptedDrift,
      },
      null,
      2,
    )}\n`,
  );

  function run(...args) {
    const result = spawnSync(process.execPath, [script, ...args], {
      cwd: root,
      encoding: 'utf8',
      timeout: 10_000,
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null, result.stderr);
    return { ...result, output: result.stdout + result.stderr };
  }

  return { run, baseline };
}

test('unchanged accepted discrepancies pass without rewriting the baseline', (t) => {
  const { run, baseline } = fixture(t);
  const before = readFileSync(baseline, 'utf8');
  const result = run();
  assert.equal(result.status, 0, result.output);
  assert.match(result.stdout, /4 known drifts \(baseline\)/);
  assert.equal(readFileSync(baseline, 'utf8'), before);
});

test('changed actual values at accepted token/platform/target identities fail', (t) => {
  for (const options of [
    { iosColor: '#444444' },
    { tailwindColor: '#444444' },
    { cssLightness: 40 },
    { iosSpacing: 24 },
  ]) {
    const { run, baseline } = fixture(t, options);
    const before = readFileSync(baseline, 'utf8');
    const result = run();
    assert.equal(result.status, 1, result.output);
    assert.match(result.stderr, /drift increased/);
    assert.match(result.stderr, /baseline stale/);
    assert.equal(readFileSync(baseline, 'utf8'), before);
  }
});

test('changed canonical values at accepted token/platform/target identities fail', (t) => {
  for (const options of [{ canonicalColor: '#010101' }, { canonicalSpacing: 24 }]) {
    const { run, baseline } = fixture(t, options);
    const before = readFileSync(baseline, 'utf8');
    const result = run();
    assert.equal(result.status, 1, result.output);
    assert.match(result.stderr, /drift increased/);
    assert.match(result.stderr, /baseline stale/);
    assert.equal(readFileSync(baseline, 'utf8'), before);
  }
});

test('a new mismatched mapping fails even when accepted discrepancies are unchanged', (t) => {
  const { run } = fixture(t, {
    map: {
      'color.semantic.background': {
        ios: 'colors.background',
        web: ['--background', 'tailwind:background', '--added'],
      },
    },
  });
  const result = run();
  assert.equal(result.status, 1, result.output);
  assert.match(result.stderr, /drift increased/);
  assert.match(result.stderr, /\(--added\): canonical=#000000 actual=#666666/);
});

test('an empty baseline passes when platform values match canonical tokens', (t) => {
  const { run } = fixture(t, {
    iosColor: '#000000',
    tailwindColor: '#000000',
    cssLightness: 0,
    iosSpacing: 16,
    drift: [],
  });
  const result = run();
  assert.equal(result.status, 0, result.output);
  assert.match(result.stdout, /0 known drifts \(baseline\)/);
});

test('fixed discrepancies require shrinking the stale baseline', (t) => {
  const { run } = fixture(t, { iosSpacing: 16 });
  const result = run();
  assert.equal(result.status, 1, result.output);
  assert.match(result.stderr, /baseline stale/);
  assert.match(result.stderr, /spacing.md/);
  assert.doesNotMatch(result.stderr, /drift increased/);
});

test('equivalent normalized hex and numeric values preserve accepted discrepancies', (t) => {
  const drift = acceptedDrift.map((entry) => ({
    actual: typeof entry.actual === 'number' ? '20.0' : ' #333 ',
    canonical: typeof entry.canonical === 'number' ? '16' : '#000',
    target: entry.target,
    platform: entry.platform,
    token: entry.token,
  }));
  const { run, baseline } = fixture(t, { drift });
  const before = readFileSync(baseline, 'utf8');
  const result = run();
  assert.equal(result.status, 0, result.output);
  assert.equal(readFileSync(baseline, 'utf8'), before);
});

test('an unchanged missing platform value matches the accepted null discrepancy', (t) => {
  const { run } = fixture(t, {
    map: { 'spacing.md': { ios: 'spacing.missing' } },
    drift: [
      ...acceptedDrift.slice(0, 3),
      { ...acceptedDrift[3], target: 'spacing.missing', actual: null },
    ],
  });
  const result = run();
  assert.equal(result.status, 0, result.output);
});

test('--update records current normalized values and the resulting baseline passes', (t) => {
  const { run, baseline } = fixture(t, { drift: [] });
  const result = run('--update');
  assert.equal(result.status, 0, result.output);
  assert.match(result.stdout, /baseline updated/);
  assert.deepEqual(JSON.parse(readFileSync(baseline, 'utf8')), {
    version: 1,
    drift: acceptedDrift,
  });
  const check = run();
  assert.equal(check.status, 0, check.output);
});
