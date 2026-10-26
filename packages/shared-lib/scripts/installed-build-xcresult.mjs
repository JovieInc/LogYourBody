import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { checkInstalledBuildXcresult } from '../src/installed-build-xcresult.ts';

function main() {
  const [manifestPath, contractPath, xcresultPath, ...extra] = process.argv.slice(2);
  if (!manifestPath || !contractPath || !xcresultPath || extra.length) {
    console.error(
      'usage: node --experimental-strip-types packages/shared-lib/scripts/installed-build-xcresult.mjs <manifest.json> <contract.json> <xcresult.json>',
    );
    return 2;
  }
  try {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    const contract = JSON.parse(readFileSync(contractPath, 'utf8'));
    const xcresult = JSON.parse(readFileSync(xcresultPath, 'utf8'));
    const result = checkInstalledBuildXcresult({ manifest, contract, xcresult });
    if (!result.ok || !result.receipt) {
      console.error(result.reasons.join('\n'));
      return 1;
    }
    process.stdout.write(`${JSON.stringify(result.receipt, null, 2)}\n`);
    return 0;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 2;
  }
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  process.exitCode = main();
}
