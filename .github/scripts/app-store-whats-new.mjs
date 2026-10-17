import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// deliver skips release notes when the platform has one App Store version
// (fastlane 2.240.1 UploadMetadata). Apple rejects that same write with
// "Attribute 'whatsNew' cannot be edited". A later version must still fail.

export function whatsNewWriteDisposition({ versionCount, errorMessage } = {}) {
  const count = Number(versionCount);
  if (!Number.isInteger(count) || count < 1) return 'failed';
  if (errorMessage == null || String(errorMessage).trim() === '') return 'written';
  const message = String(errorMessage);
  const locked = /whatsNew|whats_new/i.test(message) && /cannot be edited/i.test(message);
  if (locked && count === 1) return 'skipped-first-version';
  return 'failed';
}

function isDirectRun() {
  const entry = process.argv[1];
  return Boolean(entry) && import.meta.url === pathToFileURL(entry).href;
}

if (isDirectRun()) {
  let input;
  try {
    input = JSON.parse(readFileSync(0, 'utf8'));
  } catch {
    process.stderr.write("What's New decision input is not JSON\n");
    process.exit(2);
  }
  const disposition = whatsNewWriteDisposition(input);
  if (disposition !== 'written' && disposition !== 'skipped-first-version' && disposition !== 'failed') {
    process.exit(2);
  }
  process.stdout.write(disposition);
}
