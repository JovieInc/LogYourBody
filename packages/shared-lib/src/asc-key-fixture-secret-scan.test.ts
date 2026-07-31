import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const fixturePath = new URL('../../../scripts/test-asc-json.sh', import.meta.url);

describe('App Store Connect fixture secret guard', () => {
  it('contains only an explicitly fake, non-parseable key value', () => {
    const source = readFileSync(fixturePath, 'utf8');

    expect(source).toContain('NOT_A_REAL_PRIVATE_KEY_FIXTURE');
    expect(source).not.toMatch(/BEGIN (?:EC )?PRIVATE KEY/);
    expect(source).not.toMatch(/-----[A-Z ]+-----/);
  });
});
