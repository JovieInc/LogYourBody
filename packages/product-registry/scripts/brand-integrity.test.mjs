import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const roots = [resolve(repoRoot, 'apps/web/src'), resolve(repoRoot, 'apps/ios/LogYourBody')];
const extensions = new Set(['.ts', '.tsx', '.swift']);
const ignored = (path) =>
  path.includes('/__tests__/') ||
  path.includes('.test.') ||
  path.endsWith('/GeneratedProductRegistry.swift') ||
  path.endsWith('/landing-evaluation.ts');

async function filesIn(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry) => {
      const path = join(directory, entry.name);
      return entry.isDirectory() ? filesIn(path) : [path];
    }),
  );
  return files.flat();
}

const files = (await Promise.all(roots.map(filesIn)))
  .flat()
  .filter((path) => extensions.has(extname(path)) && !ignored(path));

const forbidden = [
  {
    pattern: /(?:support|privacy|legal|careers)@logyourbody\.com/g,
    reason: 'import the canonical contact',
  },
  {
    pattern: /com\.logyourbody\.app\.pro1\.(?:monthly|annual)/g,
    reason: 'use the generated product IDs',
  },
  { pattern: /["']\$rc_(?:monthly|annual)["']/g, reason: 'use the generated package IDs' },
  { pattern: /\$(?:5\.83|9\.99|69\.99|79\.99)/g, reason: 'use registry-derived pricing' },
  { pattern: /["']Premium["']/g, reason: 'use the generated entitlement ID' },
  {
    pattern:
      /(?:10,?000\+|10k\+|2m\+|500k\+|4\.9(?:\/5|\s+on App Store|★)|92%|93%|99\.9%|30-day money-back|DEXA-scan accuracy|Accurate to ±2%|±2% precision)/gi,
    reason: 'unsupported marketing claim',
  },
];

const failures = [];
for (const path of files) {
  const contents = await readFile(path, 'utf8');
  for (const rule of forbidden) {
    if (rule.pattern.test(contents))
      failures.push(`${path.replace(`${repoRoot}/`, '')}: ${rule.reason}`);
    rule.pattern.lastIndex = 0;
  }
}

assert.deepEqual(failures, [], `Brand registry drift:\n${failures.join('\n')}`);
