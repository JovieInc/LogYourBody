import assert from 'node:assert/strict';
import test from 'node:test';
import { BASELINE_PATH, LIMIT, scan } from './company-size-ratchet.mjs';

const CARD = 'apps/ios/LogYourBody/DesignSystem/Organisms/MetricSummaryCard.swift';

function sourceSnapshot(files) {
  return {
    files: Object.keys(files),
    readSource: (path) => {
      if (!Object.hasOwn(files, path)) throw new Error(`missing ${path}`);
      return files[path];
    },
  };
}

function baseline(entries) {
  return JSON.stringify(entries);
}

test('company size ratchet rejects growth and a new file over 500 lines', () => {
  const allowed = `${'line\n'.repeat(908)}`;
  const grown = `${'line\n'.repeat(924)}`;
  const over = `${'line\n'.repeat(LIMIT + 1)}`;
  const files = {
    [BASELINE_PATH]: baseline({ [CARD]: 908 }),
    [CARD]: grown,
    'apps/web/src/new-over.ts': over,
  };
  const findings = scan(sourceSnapshot(files));
  assert.deepEqual(
    findings.map((finding) => finding.key),
    [
      `${CARD}: grew 908 -> 924`,
      `apps/web/src/new-over.ts: ${LIMIT + 1} lines, over ${LIMIT} and not baselined`,
    ],
  );
});

test('company size ratchet accepts the recorded size, 500 lines, and skipped paths', () => {
  const files = {
    [BASELINE_PATH]: baseline({ [CARD]: 908, 'scripts/keep.py': 501 }),
    [CARD]: `${'line\n'.repeat(788)}`,
    'scripts/keep.py': `${'line\n'.repeat(501)}`,
    'scripts/at-limit.mjs': `${'line\n'.repeat(LIMIT)}`,
    'apps/ios/vendor/Generated.swift': `${'line\n'.repeat(900)}`,
    'packages/shared-lib/dist/out.js': `${'line\n'.repeat(900)}`,
    'docs/notes.md': `${'line\n'.repeat(900)}`,
    'pnpm-lock.yaml': `${'line\n'.repeat(900)}`,
  };
  assert.deepEqual(scan(sourceSnapshot(files)), []);
});
