/** @jest-environment node */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';

const tokenRoot = path.resolve(process.cwd(), '../../packages/design-tokens');
const source = JSON.parse(
  readFileSync(path.join(tokenRoot, 'web/jovie-typography-source.json'), 'utf8'),
) as {
  revision: string;
  fonts: Record<string, { sha256: string }>;
};

describe('shared Jovie typography assets', () => {
  it('ships the exact pinned upstream font files rather than renamed or substituted faces', () => {
    expect(source.revision).toMatch(/^[a-f0-9]{40}$/);
    expect(Object.keys(source.fonts).sort()).toEqual(['Inter-Latin.woff2', 'Satoshi-Latin.woff2']);
    for (const [name, font] of Object.entries(source.fonts)) {
      const bytes = readFileSync(path.join(tokenRoot, 'fonts', name));
      expect(bytes.subarray(0, 4).toString()).toBe('wOF2');
      expect(createHash('sha256').update(bytes).digest('hex')).toBe(font.sha256);
    }
  });
});
