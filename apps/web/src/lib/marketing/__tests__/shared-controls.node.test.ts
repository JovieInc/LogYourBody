/** @jest-environment node */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd(), '../..');
describe('immutable canonical Jovie controls and tokens', () => {
  it('renders the actual pinned upstream component dependency graph, with no local modifications', () => {
    const folder = path.join(root, 'packages/jovie-ui');
    const manifest = JSON.parse(readFileSync(path.join(folder, 'source.json'), 'utf8'));
    expect(manifest.repository).toBe('JovieInc/Jovie');
    expect(manifest.revision).toMatch(/^[a-f0-9]{40}$/);
    expect(Object.keys(manifest.files).sort()).toEqual([
      'atoms/button-contract.ts',
      'atoms/button.tsx',
      'atoms/input.tsx',
      'atoms/spinner.tsx',
      'lib/utils.ts',
    ]);
    for (const [name, file] of Object.entries(manifest.files) as Array<
      [string, { sha256: string }]
    >) {
      const bytes = readFileSync(path.join(folder, name));
      expect(createHash('sha256').update(bytes).digest('hex')).toBe(file.sha256);
      // Deliberate red: an edited vendor file cannot satisfy the pinned receipt.
      expect(
        createHash('sha256')
          .update(Buffer.concat([bytes, Buffer.from('// local fork')]))
          .digest('hex'),
      ).not.toBe(file.sha256);
    }
  });
  it('projects the exact exported semantic colors and records the source revision', () => {
    const folder = path.join(root, 'packages/design-tokens/web');
    const source = JSON.parse(
      readFileSync(path.join(folder, 'jovie-marketing-source.json'), 'utf8'),
    );
    const bytes = readFileSync(path.join(folder, 'jovie-colors.json'));
    expect(createHash('sha256').update(bytes).digest('hex')).toBe(source.export.sha256);
    const colors = JSON.parse(bytes.toString()).color;
    const css = readFileSync(path.join(folder, 'jovie-marketing.css'), 'utf8').replace(/\s+/g, ' ');
    for (const [role, token] of Object.entries(source.roles) as Array<[string, string]>) {
      expect(css).toContain(`--color-${role}: ${colors[token].$value};`);
    }
    for (const [name, value] of Object.entries(source.declarations))
      expect(css).toContain(`${name}: ${value};`);
  });
});
