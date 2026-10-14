import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const importer = 'apps/ios/Scripts/import-joviekit.mjs';
const manifestPath = 'apps/ios/Vendor/JovieKit.source.json';
const packagePath = 'apps/ios/Vendor/JovieKit';

function check(destination = join(root, packagePath)) {
  return execFileSync(process.execPath, [importer, 'check', manifestPath, destination], {
    cwd: root,
    encoding: 'utf8',
    timeout: 10_000,
  });
}

describe('immutable JovieKit source import', () => {
  it('verifies the committed snapshot and receipt entirely offline through the real importer', () => {
    expect(check()).toContain('18 verified files');
  });

  it.each(['policy', 'receipt', 'extra-file'])(
    'rejects %s drift in a materialized snapshot',
    (drift) => {
      const temporary = mkdtempSync(join(tmpdir(), 'lyb-joviekit-check-'));
      try {
        const destination = join(temporary, 'JovieKit');
        cpSync(join(root, packagePath), destination, { recursive: true });
        const changed =
          drift === 'policy'
            ? 'Sources/JovieKit/AppReviewPolicy.swift'
            : drift === 'receipt'
              ? '.jovie-source.json'
              : 'unexpected.swift';
        writeFileSync(join(destination, changed), 'tampered source');
        expect(() => check(destination)).toThrow();
      } finally {
        rmSync(temporary, { recursive: true, force: true });
      }
    },
  );

  it('records the tool, manifest, receipt and every package file in the existing source registry', () => {
    const registry = JSON.parse(readFileSync(join(root, 'repository-docs.json'), 'utf8'));
    const manifest = JSON.parse(readFileSync(join(root, manifestPath), 'utf8'));
    for (const destination of [
      importer,
      manifestPath,
      `${packagePath}/.jovie-source.json`,
      ...manifest.files.map((file: { path: string }) => `${packagePath}/${file.path}`),
    ]) {
      const matches = registry.imports.filter(
        (entry: { destination: string }) => entry.destination === destination,
      );
      expect(matches).toHaveLength(1);
      const entry = matches[0];
      expect(entry.repository).toBe('JovieInc/Jovie');
      expect(entry.revision).toMatch(/^[a-f0-9]{40}$/);
      expect(
        createHash('sha256')
          .update(readFileSync(join(root, destination)))
          .digest('hex'),
      ).toBe(entry.sha256);
    }
  });

  it.each([false, true])(
    'checks the snapshot before native config preparation (tampered=%s)',
    (tampered) => {
      const temporary = mkdtempSync(join(tmpdir(), 'lyb-joviekit-bootstrap-'));
      try {
        mkdirSync(join(temporary, 'Scripts'));
        mkdirSync(join(temporary, 'Vendor'));
        cpSync(join(root, importer), join(temporary, 'Scripts/import-joviekit.mjs'));
        cpSync(join(root, manifestPath), join(temporary, 'Vendor/JovieKit.source.json'));
        cpSync(join(root, packagePath), join(temporary, 'Vendor/JovieKit'), { recursive: true });
        if (tampered)
          writeFileSync(
            join(temporary, 'Vendor/JovieKit/Sources/JovieKit/AppReviewPolicy.swift'),
            'drift',
          );
        const run = () =>
          execFileSync('bash', ['scripts/ios/bootstrap-local-config.sh'], {
            cwd: root,
            env: { ...process.env, IOS_DIR: temporary },
            stdio: 'pipe',
            timeout: 10_000,
          });
        if (tampered) expect(run).toThrow();
        else expect(run).not.toThrow();
        expect(existsSync(join(temporary, 'LogYourBody/Config.xcconfig'))).toBe(!tampered);
      } finally {
        rmSync(temporary, { recursive: true, force: true });
      }
    },
  );
});
