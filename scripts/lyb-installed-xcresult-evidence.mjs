import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { checkInstalledBuildXcresult } from '../packages/shared-lib/src/installed-build-xcresult.ts';
import { launchEvidencePathIds } from './lyb-launch-manifest.mjs';

function bundleExport(directory) {
  const info = resolve(directory, 'Info.plist');
  let sha256 = '';
  try {
    sha256 = createHash('sha256').update(readFileSync(info)).digest('hex');
  } catch {
    return { sha256: '', tests: {} };
  }
  const extracted = spawnSync(
    'xcrun',
    ['xcresulttool', 'get', 'test-results', 'tests', '--path', directory],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 },
  );
  if (extracted.error || extracted.status !== 0) return { sha256: '', tests: {} };
  try {
    return { sha256, tests: JSON.parse(extracted.stdout) };
  } catch {
    return { sha256: '', tests: {} };
  }
}

function main() {
  const bundles = [];
  const args = process.argv.slice(2);
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] !== '--xcresult') {
      console.error(
        'usage: node --experimental-strip-types scripts/lyb-installed-xcresult-evidence.mjs --xcresult <bundle.xcresult> [--xcresult <bundle.xcresult> ...]',
      );
      process.exitCode = 2;
      return;
    }
    const directory = args[index + 1];
    if (!directory) {
      console.error('missing xcresult path');
      process.exitCode = 2;
      return;
    }
    bundles.push(bundleExport(resolve(directory)));
    index += 1;
  }
  if (bundles.length === 0) {
    console.error(
      'usage: node --experimental-strip-types scripts/lyb-installed-xcresult-evidence.mjs --xcresult <bundle.xcresult>',
    );
    process.exitCode = 2;
    return;
  }
  const failures = checkInstalledBuildXcresult(launchEvidencePathIds().all, bundles);
  process.stdout.write(
    `${JSON.stringify({ ok: failures.length === 0, pathCount: launchEvidencePathIds().all.length, failures }, null, 2)}\n`,
  );
  if (failures.length > 0) process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) main();
