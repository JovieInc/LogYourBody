#!/usr/bin/env node
// Blocks production deploys that would ship a Vercel sensitive-variable
// placeholder to browsers. `vercel pull` writes the literal "[SENSITIVE]" for
// sensitive variables, and a NEXT_PUBLIC_* value is inlined into client JS, so
// a sensitive NEXT_PUBLIC_* variable silently ships the placeholder (LYB-226:
// Statsig clientKey was "[SENSITIVE]" and every analytics request returned 401).
//
//   env <file>      checks the pulled env file (run after `vercel pull`)
//   bundle <dir>... scans built client output (run after `vercel build`)
//
// Failure messages name variables and files, never values.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

export const PLACEHOLDER_MARKER = '[SENSITIVE]';
export const STATSIG_CLIENT_KEY = 'NEXT_PUBLIC_STATSIG_CLIENT_KEY';

const PLACEHOLDER_WORDS = new Set([
  'placeholder', 'changeme', 'change-me', 'change_me', 'undefined', 'null', 'none', 'todo', 'tbd',
]);

export function isPlaceholder(value) {
  const normalized = value.trim().toLowerCase();
  return (
    normalized.includes(PLACEHOLDER_MARKER.toLowerCase()) ||
    PLACEHOLDER_WORDS.has(normalized) ||
    /^x+$/.test(normalized) ||
    /^\[[^\]]*\]$/.test(normalized) ||
    /^<[^>]*>$/.test(normalized) ||
    /^\$\{[^}]*\}$/.test(normalized)
  );
}

// Minimal dotenv parser matching the `KEY="value"` lines `vercel pull` writes.
export function parseEnv(contents) {
  const entries = [];
  for (const line of contents.split(/\r?\n/)) {
    const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    const quote = value[0];
    if ((quote === '"' || quote === "'") && value.lastIndexOf(quote) > 0) {
      value = value.slice(1, value.lastIndexOf(quote));
    }
    entries.push([match[1], value]);
  }
  return entries;
}

export function checkPulledEnv(contents) {
  const entries = parseEnv(contents);
  const failures = [];
  const flagged = new Set();
  for (const [name, value] of entries) {
    if (name.startsWith('NEXT_PUBLIC_') && value.toLowerCase().includes(PLACEHOLDER_MARKER.toLowerCase())) {
      flagged.add(name);
    }
  }
  for (const name of [...flagged].sort()) {
    failures.push(
      `${name} resolved to the Vercel sensitive-variable placeholder. NEXT_PUBLIC_* values are ` +
        'inlined into browser code, so mark it non-sensitive in Vercel or inject it from a GitHub secret.',
    );
  }
  const keyEntries = entries.filter(([name]) => name === STATSIG_CLIENT_KEY);
  if (keyEntries.length === 0 || !keyEntries.at(-1)[1].trim()) {
    failures.push(`${STATSIG_CLIENT_KEY} is missing or empty in the pulled production environment.`);
  } else if (isPlaceholder(keyEntries.at(-1)[1]) && !flagged.has(STATSIG_CLIENT_KEY)) {
    failures.push(`${STATSIG_CLIENT_KEY} is a placeholder value, not a Statsig client key.`);
  }
  return failures;
}

function* walk(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) yield* walk(path);
    else if (entry.isFile()) yield path;
  }
}

export function checkBundle(directories, { cwd = process.cwd() } = {}) {
  const failures = [];
  // Every requested directory must exist: a missing build output is a failure, not a pass.
  const roots = [];
  for (const directory of directories) {
    if (existsSync(directory) && statSync(directory).isDirectory()) roots.push(directory);
    else failures.push(`Built client output ${relative(cwd, directory) || directory} was not found. Refusing to pass without scanning.`);
  }
  for (const root of roots) {
    let scanned = 0;
    for (const file of walk(root)) {
      if (!/\.(?:js|mjs|css|html|json|txt)$/.test(file)) continue;
      scanned += 1;
      const contents = readFileSync(file, 'utf8');
      const count = contents.split(PLACEHOLDER_MARKER).length - 1;
      if (count > 0) {
        failures.push(
          `Built client output ${relative(cwd, file)} contains the Vercel sensitive-variable placeholder ` +
            `${count} time(s); a NEXT_PUBLIC_* variable was inlined as a placeholder.`,
        );
      }
    }
    if (scanned === 0) failures.push(`Built client output ${relative(cwd, root)} has no files to scan.`);
  }
  return failures;
}

export function run(argv, { cwd = process.cwd(), log = console } = {}) {
  const [mode, ...paths] = argv;
  let failures;
  if (mode === 'env' && paths.length === 1) {
    if (!existsSync(paths[0])) failures = [`Pulled environment file ${paths[0]} does not exist.`];
    else failures = checkPulledEnv(readFileSync(paths[0], 'utf8'));
  } else if (mode === 'bundle' && paths.length > 0) {
    failures = checkBundle(paths, { cwd });
  } else {
    failures = ['Usage: verify-public-build-env.mjs env <file> | bundle <dir>...'];
  }
  for (const failure of failures) log.error(`::error::${failure}`);
  if (failures.length === 0) log.log(`Public build environment check passed (${mode}).`);
  return failures.length === 0 ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = run(process.argv.slice(2));
}
