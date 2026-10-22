import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT } from './correction-coverage.mjs';

// Shared auth, JovieKit, design tokens and provenance links are valid LYB dependencies.
// Product-specific team IDs, client IDs and lesson namespaces must stay separate.
const teamIdentifier = ['JOVIE', 'TEAM', 'ID'].join('_').toLowerCase();
const teamId = ['bdc09edc', 'f91c', '4a06', 'b308', '74b4fcf093f8'].join('-');
const sharedIdentifiers = new Set(
  [
    'AUTH_ISSUER',
    'AUTH_CLIENT_ID',
    'AUTH_REDIRECT_URI',
    'BOT_APP_ID',
    'BOT_PRIVATE_KEY',
    'MAC_RUNNER',
  ].map((name) => `jovie_${name.toLowerCase()}`),
);
const forbidden = new RegExp(
  String.raw`\bJOVIE_[A-Z0-9_]+\b|\bjovie-(?:web|ios)\b|\bjovie\.(?:feedback-guards|correction[\w./:-]*)\b|\b${teamId}\b`,
  'gi',
);

export const EXCEPTIONS = {
  '.github/scripts/lib/linear-issue-intake.mjs': {
    reason:
      'Retained upstream adapter defaults; LYB intake callers explicitly resolve their own team.',
    identifiers: { [teamIdentifier]: 5, [teamId]: 1 },
  },
  '.github/scripts/remediation-signal.test.mjs': {
    reason: 'Existing compatibility tests exercise the vendored adapter defaults.',
    identifiers: { [teamIdentifier]: 3 },
  },
  'scripts/setup-gbrain.sh': {
    reason: 'AGENTS.md requires retaining GBrain Doppler reads against the shared configuration.',
    identifiers: { [['jovie', 'web'].join('-')]: 2 },
  },
};

export function runSeparation({ root = ROOT, exceptions = EXCEPTIONS } = {}) {
  for (const exception of Object.values(exceptions))
    assert.ok(exception.reason?.trim(), 'Jovie separation exception reason required');
  const paths = execFileSync(
    'git',
    [
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
      '--',
      'apps',
      'agent',
      'packages',
      'scripts',
      '.github',
    ],
    { cwd: root, encoding: 'utf8' },
  )
    .split('\0')
    .filter(Boolean);
  const counts = new Map();
  const violations = [];
  let scanned = 0;
  for (const path of new Set(paths)) {
    if (
      !/\.(?:[cm]?[jt]sx?|swift|sh|py|rb|sql|ya?ml|json|toml|xcconfig(?:\.template)?)$/u.test(path)
    )
      continue;
    const absolute = join(root, path);
    // Deleted tracked files have no current source. Never follow imported symlinks.
    if (!lstatSync(absolute, { throwIfNoEntry: false })?.isFile()) continue;
    scanned++;
    const lines = readFileSync(absolute, 'utf8').split(/\r?\n/u);
    for (const [index, line] of lines.entries()) {
      for (const match of line.matchAll(forbidden)) {
        const identifier = match[0].toLowerCase();
        if (sharedIdentifiers.has(identifier)) continue;
        const key = `${path}:${identifier}`;
        const count = (counts.get(key) ?? 0) + 1;
        counts.set(key, count);
        if (count > (exceptions[path]?.identifiers[identifier] ?? 0))
          violations.push(`${path}:${index + 1}: ${match[0]}`);
      }
    }
  }
  assert.ok(scanned > 0, 'Jovie separation: no LYB code found to scan');
  assert.equal(violations.length, 0, `Jovie separation failed:\n${violations.join('\n')}`);
  return { scanned };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    assert.equal(process.argv.length, 2, 'usage: jovie-separation.mjs');
    const { scanned } = runSeparation();
    console.log(`Jovie separation passed; scanned ${scanned} LYB code files.`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
