import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

// Exercise the configured SwiftLint rule, rather than a second scanner expression.
const config = readFileSync(new URL('../../../apps/ios/.swiftlint.yml', import.meta.url), 'utf8');
const rule = config.split('  xctskip_message:\n')[1]?.split('\n  no_hardcoded_strings:')[0] ?? '';
const pattern = new RegExp(rule.match(/regex: '([^\n]+)'/)?.[1] ?? '(?!)');

it.each(['describing', 'reflecting'])('rejects %s a positively identified XCTSkip', (label) => {
  expect(rule).toContain('severity: error');
  expect(
    pattern.test(`XCTAssertTrue(caught is XCTSkip)
      XCTAssertTrue(String(${label}: caught).contains("SecItemAdd returned"))`),
  ).toBe(true);
});

it('allows the public skip message and descriptions of other error types', () => {
  expect(
    pattern.test(`XCTAssertTrue(error is XCTSkip)
      XCTAssertEqual((error as? XCTSkip)?.message, "capability unavailable")`),
  ).toBe(false);
  expect(pattern.test('XCTAssertTrue(String(describing: error).contains("SecItemDelete"))')).toBe(
    false,
  );
  expect(
    pattern.test(`XCTAssertTrue(error is XCTSkip)
      }
      XCTAssertTrue(String(describing: error).contains("SecItemDelete"))`),
  ).toBe(false);
});

it('keeps native tests free of reflected skip assertions and hashes their sources', () => {
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  expect(turbo.tasks.test.inputs).toContain('$TURBO_ROOT$/apps/ios/.swiftlint.yml');
  for (const directory of ['LogYourBodyTests', 'LogYourBodyUITests']) {
    const root = fileURLToPath(new URL(`../../../apps/ios/${directory}/`, import.meta.url));
    const violations = readdirSync(root, { recursive: true })
      .map(String)
      .filter((path) => path.endsWith('.swift'))
      .filter((path) => pattern.test(readFileSync(join(root, path), 'utf8')));
    expect(violations).toEqual([]);
    expect(turbo.tasks.test.inputs).toContain(`$TURBO_ROOT$/apps/ios/${directory}/**/*.swift`);
  }
});
