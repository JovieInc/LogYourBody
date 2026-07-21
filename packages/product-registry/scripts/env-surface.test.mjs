#!/usr/bin/env node
// Env surface guard.
// iOS: keys read by Utils/Configuration.swift must be declared in a Config
// template, the release-config script, or the active Info.plist; keys declared
// in the templates must be reachable through the active Info.plist.
// Web: process.env keys read in apps/web/src (non-test) must be declared in
// apps/web/.env.example. Declared-but-never-consumed is report-only.
// Runs in the package `test` script (required CI `js` job).
import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import console from 'node:console';
import process from 'node:process';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');

// Explicit exceptions: { key, reason }. Keep empty unless a key is genuinely
// optional outside the normal declaration chain.
const iosExceptions = [];
const webExceptions = [
  { key: 'NODE_ENV', reason: 'Node/Next.js framework-provided' },
  { key: 'VERCEL_ENV', reason: 'Vercel platform-provided' },
  { key: 'NEXT_PUBLIC_VERCEL_ENV', reason: 'Vercel platform-provided' },
];

const keysMatching = (contents, pattern) =>
  new Set([...contents.matchAll(pattern)].map((match) => match[1]));

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

const failures = [];

// -- iOS ---------------------------------------------------------------------

const iosDir = 'apps/ios';
const configuration = await readFile(
  resolve(repoRoot, iosDir, 'LogYourBody/Utils/Configuration.swift'),
  'utf8',
);
const consumed = keysMatching(
  configuration,
  /(?:stringValue|boolValue|value)\(for:\s*"([A-Z_][A-Z0-9_]*)"/g,
);

const templateFiles = [
  `${iosDir}/LogYourBody/Config-Production.xcconfig.template`,
  `${iosDir}/LogYourBody/Config-Development.xcconfig.template`,
];
const templateKeys = new Set();
for (const file of templateFiles) {
  const contents = await readFile(resolve(repoRoot, file), 'utf8');
  for (const key of keysMatching(contents, /^([A-Z_][A-Z0-9_]*)\s*=/gm)) templateKeys.add(key);
}

const releaseScript = await readFile(
  resolve(repoRoot, `${iosDir}/Scripts/write_release_config.sh`),
  'utf8',
);
const scriptKeys = keysMatching(releaseScript, /^([A-Z_][A-Z0-9_]*)\s*=/gm);

// Active plist (project.pbxproj INFOPLIST_FILE = LogYourBody/Info.plist).
const plist = await readFile(resolve(repoRoot, `${iosDir}/LogYourBody/Info.plist`), 'utf8');
const plistKeys = keysMatching(plist, /<key>([A-Z_][A-Z0-9_]*)<\/key>/g);

const declared = new Set([...templateKeys, ...scriptKeys, ...plistKeys]);
const excepted = (key, exceptions) => exceptions.some((entry) => entry.key === key);

for (const key of [...consumed].sort()) {
  if (!declared.has(key) && !excepted(key, iosExceptions)) {
    failures.push(`iOS consumes ${key} but no template, release script, or Info.plist declares it`);
  }
}
for (const key of [...templateKeys].sort()) {
  if (!plistKeys.has(key) && !excepted(key, iosExceptions)) {
    failures.push(`iOS templates declare ${key} but the active Info.plist cannot reach it`);
  }
}

// -- Web ---------------------------------------------------------------------

const webSrc = resolve(repoRoot, 'apps/web/src');
const webFiles = (await filesIn(webSrc, ['.ts', '.tsx'])).filter(
  (path) => !path.includes('/__tests__/') && !path.includes('.test.'),
);
const webConsumed = new Set();
for (const path of webFiles) {
  const contents = await readFile(path, 'utf8');
  for (const key of keysMatching(contents, /process\.env\.([A-Z_][A-Z0-9_]*)/g)) {
    webConsumed.add(key);
  }
}

const envExample = await readFile(resolve(repoRoot, 'apps/web/.env.example'), 'utf8');
const webDeclared = keysMatching(envExample, /^([A-Z_][A-Z0-9_]*)=/gm);

for (const key of [...webConsumed].sort()) {
  if (!webDeclared.has(key) && !excepted(key, webExceptions)) {
    failures.push(`web consumes process.env.${key} but apps/web/.env.example does not declare it`);
  }
}
const webUnused = [...webDeclared].filter((key) => !webConsumed.has(key)).sort();
for (const key of webUnused) {
  console.warn(`warn: apps/web/.env.example declares ${key} but nothing consumes it`);
}

// -- Report ------------------------------------------------------------------

if (failures.length > 0) {
  console.error(`Env surface guard failed (${failures.length}):`);
  for (const failure of failures) console.error(`  ${failure}`);
  process.exit(1);
}

console.log(
  `Env surface guard: ok — ${consumed.size} iOS consumed keys declared, ${webConsumed.size} web consumed keys declared`,
);
