import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const staged = process.argv.includes('--staged');
const read = (name) =>
  staged
    ? execFileSync('git', ['show', `:${name}`], { cwd: root })
    : readFileSync(path.join(root, name));
const files = [
  'atoms/button-contract.ts',
  'atoms/button.tsx',
  'atoms/input.tsx',
  'atoms/spinner.tsx',
  'lib/utils.ts',
];
const source = JSON.parse(read('packages/jovie-ui/source.json').toString());
if (
  source.repository !== 'JovieInc/Jovie' ||
  !/^[a-f0-9]{40}$/.test(source.revision) ||
  JSON.stringify(Object.keys(source.files).sort()) !== JSON.stringify(files)
) {
  throw new Error(
    'Unexpected Jovie import manifest. Review upstream ownership before changing the exact import set.',
  );
}
for (const name of files) {
  const digest = createHash('sha256')
    .update(read(`packages/jovie-ui/${name}`))
    .digest('hex');
  if (digest !== source.files[name].sha256)
    throw new Error(`Immutable Jovie import changed: ${name}`);
}
const tokens = JSON.parse(
  read('packages/design-tokens/web/jovie-marketing-source.json').toString(),
);
if (
  tokens.revision !== source.revision ||
  createHash('sha256')
    .update(read('packages/design-tokens/web/jovie-colors.json'))
    .digest('hex') !== tokens.export.sha256
) {
  throw new Error('Immutable Jovie color export does not match its source receipt.');
}
console.log(
  `Verified ${files.length} immutable Jovie controls and color export at ${source.revision}.`,
);
