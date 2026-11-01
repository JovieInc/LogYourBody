/**
 * @jest-environment node
 */
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import productAssets from '@/generated/marketing-product-assets.json';

function sha256(filePath: string) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

describe('canonical marketing product assets', () => {
  it('keeps the public product screenshot byte-identical to the iOS Fastlane capture', () => {
    const root = path.resolve(process.cwd(), '../..');
    const source = path.join(root, productAssets.weightLog.source);
    const output = path.join(root, productAssets.weightLog.output);

    expect(sha256(source)).toBe(productAssets.weightLog.sourceSha256);
    expect(sha256(output)).toBe(productAssets.weightLog.outputSha256);
    expect(productAssets.weightLog.sourceSha256).toBe(productAssets.weightLog.outputSha256);
  });

  it('requires a recent canonical product capture for marketing use', () => {
    const ageMs = Date.now() - Date.parse(productAssets.weightLog.capturedAt);
    expect(ageMs).toBeGreaterThanOrEqual(0);
    expect(ageMs).toBeLessThanOrEqual(60 * 24 * 60 * 60 * 1000);
  });

  it('records actual PNG dimensions instead of advertising a viewport guess', () => {
    expect(productAssets.weightLog).toEqual(expect.objectContaining({ width: 1320, height: 2868 }));
    expect(productAssets.appIcon).toEqual(expect.objectContaining({ width: 1024, height: 1024 }));
  });

  it('preserves capture provenance across shallow merge builds and source archives', () => {
    const root = path.resolve(process.cwd(), '../..');
    const temporary = mkdtempSync(path.join(os.tmpdir(), 'lyb-marketing-provenance-'));
    const source = path.join(temporary, 'source');
    const checkout = path.join(temporary, 'checkout');
    const script = 'scripts/marketing/sync-ios-marketing-assets.mjs';
    const manifest = 'apps/web/src/generated/marketing-product-assets.json';
    const captureDate = '2026-10-20T19:36:52-07:00';
    const git = (...args: string[]) => execFileSync('git', args, { cwd: source, stdio: 'pipe' });
    const commit = (date: string) => {
      git('add', '.');
      execFileSync(
        'git',
        [
          '-c',
          'user.name=Fixture',
          '-c',
          'user.email=fixture@example.test',
          '-c',
          'core.hooksPath=/dev/null',
          'commit',
          '-m',
          'capture fixture',
        ],
        {
          cwd: source,
          stdio: 'pipe',
          env: { ...process.env, GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date },
        },
      );
    };
    try {
      for (const file of [
        script,
        manifest,
        ...Object.values(productAssets).map((asset) => asset.source),
      ]) {
        mkdirSync(path.dirname(path.join(source, file)), { recursive: true });
        copyFileSync(path.join(root, file), path.join(source, file));
      }
      git('init', '--initial-branch=main');
      commit(captureDate);
      writeFileSync(path.join(source, 'unrelated.txt'), 'synthetic merge');
      commit('2099-01-01T00:00:00Z');
      git('clone', '--depth=1', pathToFileURL(source).href, checkout);
      const sync = (directory: string) => {
        execFileSync(process.execPath, [path.join(directory, script)], { stdio: 'pipe' });
        return JSON.parse(readFileSync(path.join(directory, manifest), 'utf8'));
      };
      expect(
        execFileSync('git', ['rev-parse', '--is-shallow-repository'], {
          cwd: checkout,
          encoding: 'utf8',
        }).trim(),
      ).toBe('true');
      expect(sync(checkout)).toEqual(productAssets);
      expect(sync(checkout)).toEqual(productAssets);
      rmSync(path.join(checkout, '.git'), { recursive: true });
      expect(sync(checkout)).toEqual(productAssets);

      // A changed source must obtain fresh provenance instead of retaining the old receipt.
      const changed = path.join(source, productAssets.weightLog.source);
      writeFileSync(changed, Buffer.concat([readFileSync(changed), Buffer.from('changed')]));
      const changedDate = '2026-10-21T12:00:00Z';
      commit(changedDate);
      const updated = sync(source);
      expect(Date.parse(updated.weightLog.capturedAt)).toBe(Date.parse(changedDate));
      expect(updated.weightLog.sourceSha256).not.toBe(productAssets.weightLog.sourceSha256);
      expect(updated.weightLog.outputSha256).toBe(updated.weightLog.sourceSha256);
      for (const invalidReceipt of [
        { ...updated.weightLog, capturedAt: 'invalid' },
        { ...updated.weightLog, source: 'another.png', capturedAt: captureDate },
      ]) {
        writeFileSync(
          path.join(source, manifest),
          JSON.stringify({ ...updated, weightLog: invalidReceipt }),
        );
        expect(sync(source).weightLog).toEqual(updated.weightLog);
      }
    } finally {
      rmSync(temporary, { recursive: true, force: true });
    }
  });
});
