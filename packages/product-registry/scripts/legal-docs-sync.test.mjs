#!/usr/bin/env node
// Legal docs drift guard. shared/legal is canonical; the iOS app ships
// byte-identical copies (sync via apps/ios/copy-legal-docs.sh). Contact
// emails must live on logyourbody.com (registry identity.domain).
// Runs in the package `test` script (required CI `js` job).
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import console from 'node:console';
import process from 'node:process';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const sharedDir = resolve(repoRoot, 'shared/legal');
const iosDir = resolve(repoRoot, 'apps/ios/LogYourBody/Resources/Legal');
const webLoader = resolve(repoRoot, 'apps/web/src/lib/load-legal-docs.ts');

const sha256 = async (path) => createHash('sha256').update(await readFile(path)).digest('hex');

const failures = [];
const docs = (await readdir(sharedDir)).filter((name) => name.endsWith('.md')).sort();

for (const doc of docs) {
  const sharedHash = await sha256(join(sharedDir, doc));
  const iosHash = await sha256(join(iosDir, doc)).catch(() => null);
  if (iosHash === null) {
    failures.push(`${doc}: missing iOS copy; run apps/ios/copy-legal-docs.sh`);
  } else if (iosHash !== sharedHash) {
    failures.push(`${doc}: iOS copy differs from shared/legal; run apps/ios/copy-legal-docs.sh`);
  }
}

const emailPattern = /[\w.+-]+@logyourbody\.app\b/i;
for (const path of [...docs.map((doc) => join(sharedDir, doc)), webLoader]) {
  const contents = await readFile(path, 'utf8');
  const match = contents.match(emailPattern);
  if (match) failures.push(`${path}: ${match[0]} must use the logyourbody.com domain`);
}

if (failures.length > 0) {
  console.error(`Legal docs sync guard failed (${failures.length}):`);
  for (const failure of failures) console.error(`  ${failure}`);
  process.exit(1);
}

console.log(`Legal docs sync guard: ok — ${docs.length} docs byte-identical, emails on canonical domain`);
