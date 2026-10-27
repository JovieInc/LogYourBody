import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

// SwiftUI exposes this system preference as a get-only EnvironmentValues property.
const writesReduceMotion = (source: string) =>
  /\.environment\s*\(\s*\\\s*\.\s*accessibilityReduceMotion\s*,/.test(source);

// Independent feature merges can silently duplicate an environment binding.
const duplicateEnvironmentBindings = (source: string) => {
  const scopes = [new Set<string>()];
  const duplicates: string[] = [];
  const tokens = source.matchAll(
    /\/\/[^\n]*|\/\*[\s\S]*?\*\/|"""[\s\S]*?"""|"(?:\\[\s\S]|[^"\\])*"|[{}]|@\s*Environment\s*\([^)]*\)\s*(?:(?:private|fileprivate|internal|public)\s+)?var\s+(\w+)/g,
  );
  for (const [token, binding] of tokens) {
    if (token === '{') scopes.push(new Set());
    else if (token === '}' && scopes.length > 1) scopes.pop();
    else if (binding) {
      const scope = scopes[scopes.length - 1];
      if (scope.has(binding)) duplicates.push(binding);
      scope.add(binding);
    }
  }
  return duplicates;
};

it('rejects silently merged environment redeclarations within the same scope', () => {
  expect(
    duplicateEnvironmentBindings(String.raw`
    struct Workout: View {
      @Environment(\.dynamicTypeSize) private var dynamicTypeSize
      @Environment(
        \.dynamicTypeSize
      ) private var dynamicTypeSize
    }
  `),
  ).toEqual(['dynamicTypeSize']);
});

it('allows independent view bindings and ignores comments and strings', () => {
  expect(
    duplicateEnvironmentBindings(String.raw`
    struct Workout: View {
      @Environment(\.theme) private var theme
      // @Environment(\.theme) private var theme }
      /* @Environment(\.theme) private var theme { */
      let copy = "@Environment(\.theme) private var theme }"
      let multiline = """
      @Environment(\.theme) private var theme {
      """
      struct Nested: View { @Environment(\.theme) var theme }
    }
    struct Plan: View { @Environment(\.theme) var theme }
  `),
  ).toEqual([]);
});

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

it('keeps merged native views free of duplicate environment bindings', () => {
  const root = fileURLToPath(new URL('../../../apps/ios/LogYourBody/', import.meta.url));
  const violations = readdirSync(root, { recursive: true })
    .map(String)
    .filter((path) => path.endsWith('.swift'))
    .flatMap((path) =>
      duplicateEnvironmentBindings(readFileSync(join(root, path), 'utf8')).map(
        (binding) => `${path}: ${binding}`,
      ),
    );

  expect(violations, 'Retain one environment binding per scope when merging native views').toEqual(
    [],
  );
});
