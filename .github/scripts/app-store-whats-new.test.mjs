import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { whatsNewWriteDisposition } from './app-store-whats-new.mjs';

const FIRST_VERSION_REJECTION = [
  'An exception has occurred for locale: en-US.',
  "Error: The request cannot be fulfilled because of the state of another resource. - Attribute 'whatsNew' cannot be edited at this time",
].join('\n');

test('the only App Store version may skip the whatsNew edit lock', () => {
  assert.equal(
    whatsNewWriteDisposition({ versionCount: 1, errorMessage: FIRST_VERSION_REJECTION }),
    'skipped-first-version',
  );
  assert.equal(
    whatsNewWriteDisposition({
      versionCount: 1,
      errorMessage: "Attribute 'whats_new' cannot be edited at this time",
    }),
    'skipped-first-version',
  );
});

test('a second version and every other rejection still fail', () => {
  assert.equal(
    whatsNewWriteDisposition({ versionCount: 2, errorMessage: FIRST_VERSION_REJECTION }),
    'failed',
  );
  assert.equal(
    whatsNewWriteDisposition({
      versionCount: 1,
      errorMessage: "You must provide a value for the attribute 'whatsNew' with this request",
    }),
    'failed',
  );
  assert.equal(whatsNewWriteDisposition({ versionCount: 1, errorMessage: 'unauthorized' }), 'failed');
  assert.equal(whatsNewWriteDisposition({ versionCount: 0, errorMessage: FIRST_VERSION_REJECTION }), 'failed');
  assert.equal(whatsNewWriteDisposition({ versionCount: 1.5, errorMessage: FIRST_VERSION_REJECTION }), 'failed');
  assert.equal(whatsNewWriteDisposition({ errorMessage: FIRST_VERSION_REJECTION }), 'failed');
});

test('a completed write is not an error', () => {
  assert.equal(whatsNewWriteDisposition({ versionCount: 1, errorMessage: null }), 'written');
  assert.equal(whatsNewWriteDisposition({ versionCount: 2, errorMessage: '  ' }), 'written');
});

test('the decision CLI prints a disposition and does not fail the skip itself', () => {
  const skipped = spawnSync(process.execPath, [new URL('./app-store-whats-new.mjs', import.meta.url).pathname], {
    input: JSON.stringify({ versionCount: 1, errorMessage: FIRST_VERSION_REJECTION }),
    encoding: 'utf8',
  });
  assert.equal(skipped.status, 0);
  assert.equal(skipped.stdout, 'skipped-first-version');

  const failed = spawnSync(process.execPath, [new URL('./app-store-whats-new.mjs', import.meta.url).pathname], {
    input: JSON.stringify({ versionCount: 2, errorMessage: FIRST_VERSION_REJECTION }),
    encoding: 'utf8',
  });
  assert.equal(failed.status, 0);
  assert.equal(failed.stdout, 'failed');

  const invalid = spawnSync(process.execPath, [new URL('./app-store-whats-new.mjs', import.meta.url).pathname], {
    input: '{',
    encoding: 'utf8',
  });
  assert.equal(invalid.status, 2);
});

test('metadata sync consults the decision before failing a whatsNew lock', () => {
  const workflow = readFileSync(new URL('../workflows/app-store-metadata-sync.yml', import.meta.url), 'utf8');
  assert.match(workflow, /whats_new: notes/);
  assert.match(workflow, /get_app_store_versions/);
  assert.match(workflow, /app-store-whats-new\.mjs/);
  assert.match(workflow, /versionCount/);
  assert.match(workflow, /skipped-first-version/);
  const redaction = workflow.indexOf('PRIVATE KEY');
  const helper = workflow.indexOf('app-store-whats-new.mjs');
  assert.equal(redaction >= 0 && helper > redaction, true);
  assert.match(workflow, /upload_to_app_store/);
  assert.match(workflow, /skip_binary_upload:true/);
  assert.match(workflow, /submit_for_review:false/);
});
