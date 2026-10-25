import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const chartPath = fileURLToPath(
  new URL('../../../apps/ios/LogYourBody/Views/HomeV2/HomeV2TrendChart.swift', import.meta.url),
);

it('keeps full-history plot preparation outside each chart sample closure (LYB-181)', () => {
  const source = readFileSync(chartPath, 'utf8');
  // `plotted` sorts, filters, and normalizes the entire history on every read.
  // Reading it in a sample closure made the work quadratic, causing app hangs.
  const sampleClosures = Array.from(
    source.matchAll(/^(\s*)ForEach\([^\n]+\) \{ sample in\n([\s\S]*?)^\1\}/gm),
  );

  expect(sampleClosures.length).toBeGreaterThan(0);
  for (const [, , body] of sampleClosures) {
    expect(body, 'Use a plot snapshot captured before ForEach').not.toMatch(/\bplotted\b/);
    expect(body).not.toMatch(/HomeV2ChartIntegrity\.(?:plot|filter)\s*\(/);
  }
});

it('retains the gated, view-owned chart preparation cache during playhead updates (LYB-44)', () => {
  const source = readFileSync(chartPath, 'utf8');
  expect(source).toContain(
    '@State private var preparationCache = HomeV2ChartIntegrity.PreparationCache()',
  );
  expect(source).toContain('isFeatureEnabled(flagKey: "chart_playhead_v2")');
  expect(source).toContain('return preparationCache.value(for: request)');
  expect(source).toContain('if responsivePlayheadEnabled { return preparation.plot }');
  expect(source).toContain('prefersLatestReading: false');
  expect(source).toContain('guard next != selectedX else { return }');
  expect(source).toMatch(
    /onChange\(of: responsivePlayheadEnabled \? plotted\.selectionSamples : \[\]\)[\s\S]*?if responsivePlayheadEnabled \{ selectedX = nil \}/,
  );
  expect(source).not.toMatch(/HomeV2ChartIntegrity\.(?:filter|nearest)\s*\(/);
});
