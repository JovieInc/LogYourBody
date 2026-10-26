import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Finds real fastlane failures in a tee'd log. The step's exit status (with
// `set -o pipefail`) is the primary gate; this scan is a second check that
// names the failing lines in the job summary.
//
// fastlane prints its release changelog when a newer gem exists. Those bullet
// lines contain arbitrary words ("signing", "duplicate", "has to fail"), so a
// loose grep fails healthy runs. Only fastlane's own failure markers count.

const ANSI = /\u001b\[[0-9;]*[A-Za-z]/g;
const TIMESTAMP = /^\[\d{2}:\d{2}:\d{2}\]: /;

const FAILURE_PATTERNS = [
  /^\[!\] /, // fastlane fatal error (UI.user_error! / crash)
  /found one or more potential problems that must be addressed/, // precheck rule failures
  /^\|?\s*Failed rules\s*\|?$/, // precheck failed-rules table title
  /ERROR ITMS-\d+/, // Apple upload / validation rejection
];

function isChangelogLine(line) {
  // "* [scope] change (#123) via Name" bullets and the "#####" update banner.
  return line.startsWith('* ') || line.startsWith('#');
}

export function fastlaneFailureLines(log) {
  return String(log ?? '')
    .split(/\r?\n/)
    .map((raw) => raw.replace(ANSI, '').replace(TIMESTAMP, '').trim())
    .filter((line) => line !== '' && !isChangelogLine(line))
    .filter((line) => FAILURE_PATTERNS.some((pattern) => pattern.test(line)));
}

function isDirectRun() {
  const entry = process.argv[1];
  return Boolean(entry) && import.meta.url === pathToFileURL(entry).href;
}

if (isDirectRun()) {
  const path = process.argv[2];
  if (!path) {
    process.stderr.write('usage: fastlane-log-failures.mjs <log-file>\n');
    process.exit(2);
  }
  const failures = fastlaneFailureLines(readFileSync(path, 'utf8'));
  for (const line of failures) process.stdout.write(`${line}\n`);
  process.exit(failures.length > 0 ? 1 : 0);
}
