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
