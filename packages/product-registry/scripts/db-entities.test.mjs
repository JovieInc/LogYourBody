#!/usr/bin/env node
// DB entities drift guard. Table/bucket names referenced from Supabase edge
// functions and web non-test code must exist in the canonical registry lists
// (endpoints.tables / endpoints.buckets). Catches the phantom-table class
// (e.g. a sync manager writing to a `user_profiles` table that no migration
// creates). Fixtures and tests are exempt. Runs in the package `test`
// script (required CI `js` job).
import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import console from 'node:console';
import process from 'node:process';
import { logYourBody } from '../src/products/logyourbody.mjs';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const { tables, buckets } = logYourBody.endpoints;

// Explicit exceptions: { name, reason }.
const exceptions = [
  {
    name: '_',
    reason: 'DatabaseStatus connectivity probe intentionally targets a nonexistent table',
  },
];

const allowed = new Set([...tables, ...buckets, ...exceptions.map((entry) => entry.name)]);
const patterns = [
  /\.from\(\s*['"]([\w]+)['"]/g, // supabase-js table or storage bucket
  /\binsert\s+into\s+(?:public\.)?["'`]?([a-z][a-z0-9_]*)["'`]?/g, // raw SQL
  /\btable\s+"([a-z][a-z0-9_]*)"/g, // DDL-style reference
];

async function filesIn(directory, extensions) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await filesIn(path, extensions)));
    else if (extensions.some((ext) => entry.name.endsWith(ext))) files.push(path);
  }
  return files;
}

const roots = [resolve(repoRoot, 'supabase/functions'), resolve(repoRoot, 'apps/web/src')];
const files = (
  await Promise.all(roots.map((root) => filesIn(root, ['.ts', '.tsx'])))
)
  .flat()
  .filter((path) => !path.includes('/__tests__/') && !path.includes('.test.'));

const failures = [];
for (const path of files) {
  const contents = await readFile(path, 'utf8');
  for (const pattern of patterns) {
    for (const match of contents.matchAll(pattern)) {
      const name = match[1];
      if (!allowed.has(name)) {
        failures.push(
          `${path.replace(`${repoRoot}/`, '')}: '${name}' is not in endpoints.tables/buckets`,
        );
      }
    }
  }
}

if (failures.length > 0) {
  console.error(`DB entities guard failed (${failures.length}):`);
  for (const failure of failures) console.error(`  ${failure}`);
  process.exit(1);
}

console.log(
  `DB entities guard: ok — ${files.length} files scanned, ${tables.length} tables + ${buckets.length} buckets canonical`,
);
