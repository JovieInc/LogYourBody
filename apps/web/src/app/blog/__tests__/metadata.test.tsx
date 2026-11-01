import { readFileSync } from 'node:fs';
import path from 'node:path';

describe('hidden blog routes', () => {
  it('returns article URLs to the launch entry', () => {
    for (const file of ['../[slug]/page.tsx', '../tag/[tag]/page.tsx', '../page.tsx']) {
      const source = readFileSync(path.join(__dirname, file), 'utf8');
      expect(source).toContain("redirect('/')");
      expect(source).not.toContain('generateMetadata');
      expect(source).not.toMatch(/<[A-Za-z]/);
    }
  });
});
