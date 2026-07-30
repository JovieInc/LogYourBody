import console from 'node:console';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { expectedStorefrontFiles } from './storefront-files.mjs';

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = resolve(packageRoot, '../..');
const check = process.argv.includes('--check');
const files = await expectedStorefrontFiles(repoRoot);

for (const [path, content] of files) {
  if (check) {
    const current = await readFile(path, 'utf8').catch(() => '');
    if (current !== content) {
      throw new Error(`${path} is stale; run pnpm product:generate`);
    }
    continue;
  }

  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content);
}

console.log(
  check
    ? `Validated ${files.size} generated App Store storefront files.`
    : `Generated ${files.size} App Store storefront files.`,
);
