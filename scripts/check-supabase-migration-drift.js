#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');
const authoritativeDir = path.join(repoRoot, 'supabase', 'migrations');
const legacyDir = path.join(repoRoot, 'apps', 'web', 'supabase', 'migrations');
const ignoredSqlFiles = new Set(['template.sql']);

function listMigrationFiles(dir) {
  if (!fs.existsSync(dir)) {
    return [];
  }

  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((filename) => filename.endsWith('.sql'))
    .filter((filename) => !ignoredSqlFiles.has(filename))
    .sort();
}

function hashFile(filepath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filepath)).digest('hex');
}

function relative(filepath) {
  return path.relative(repoRoot, filepath);
}

function printList(title, items) {
  if (items.length === 0) {
    return;
  }

  console.log(`\n${title}`);
  for (const item of items) {
    console.log(`  - ${item}`);
  }
}

function main() {
  if (!fs.existsSync(authoritativeDir)) {
    console.error(`Missing authoritative migration root: ${relative(authoritativeDir)}`);
    process.exit(1);
  }

  const authoritativeFiles = listMigrationFiles(authoritativeDir);
  const legacyFiles = listMigrationFiles(legacyDir);
  const authoritativeSet = new Set(authoritativeFiles);
  const legacySet = new Set(legacyFiles);

  const authoritativeOnly = authoritativeFiles.filter((filename) => !legacySet.has(filename));
  const legacyOnly = legacyFiles.filter((filename) => !authoritativeSet.has(filename));
  const contentMismatches = authoritativeFiles.filter((filename) => {
    if (!legacySet.has(filename)) {
      return false;
    }

    const authoritativeHash = hashFile(path.join(authoritativeDir, filename));
    const legacyHash = hashFile(path.join(legacyDir, filename));
    return authoritativeHash !== legacyHash;
  });

  console.log('Supabase migration drift check');
  console.log(
    `  Authoritative root: ${relative(authoritativeDir)} (${authoritativeFiles.length} migrations)`,
  );
  console.log(`  Legacy web mirror:  ${relative(legacyDir)} (${legacyFiles.length} migrations)`);

  printList(
    'Authoritative-only migrations (legacy mirror is incomplete; this is reported, not failed):',
    authoritativeOnly,
  );
  printList('Unsafe legacy-only migrations:', legacyOnly);
  printList('Unsafe same-filename content mismatches:', contentMismatches);

  if (legacyOnly.length > 0 || contentMismatches.length > 0) {
    console.error(
      '\nUnsafe Supabase migration drift detected. Add new migrations only under supabase/migrations, ' +
        'then reconcile or retire the legacy apps/web/supabase/migrations copy before enabling this guard in CI.',
    );
    process.exit(1);
  }

  console.log('\nNo unsafe Supabase migration drift detected.');
}

main();
