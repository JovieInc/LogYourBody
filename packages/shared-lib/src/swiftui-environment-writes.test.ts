import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

// SwiftUI exposes this system preference as a get-only EnvironmentValues property.
const writesReduceMotion = (source: string) =>
  /\.environment\s*\(\s*\\\s*\.\s*accessibilityReduceMotion\s*,/.test(source);

it.each([
  String.raw`.environment(\.accessibilityReduceMotion, true)`,
  String.raw`.environment(
    \.accessibilityReduceMotion,
    false
  )`,
])('rejects a write to the read-only Reduce Motion environment: %s', (source) => {
  expect(writesReduceMotion(source)).toBe(true);
});

it('allows reading Reduce Motion and setting writable preview preferences', () => {
  expect(
    writesReduceMotion(String.raw`
      @Environment(\.accessibilityReduceMotion) private var reduceMotion
      TrainingNumericScrubPreview().environment(\.dynamicTypeSize, .accessibility3)
    `),
  ).toBe(false);
});

it('keeps native views and previews free of read-only Reduce Motion writes (LYB-153)', () => {
  const root = fileURLToPath(new URL('../../../apps/ios/LogYourBody/', import.meta.url));
  const violations = readdirSync(root, { recursive: true })
    .map(String)
    .filter((path) => path.endsWith('.swift'))
    .filter((path) => writesReduceMotion(readFileSync(join(root, path), 'utf8')));

  expect(
    violations,
    'Use the system Reduce Motion preference; its environment value is read-only',
  ).toEqual([]);
});
