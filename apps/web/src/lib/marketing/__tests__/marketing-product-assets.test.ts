/**
 * @jest-environment node
 */
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
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
});

describe('marketing asset sync provenance', () => {
  const root = path.resolve(process.cwd(), '../..');
  const script = 'scripts/marketing/sync-ios-marketing-assets.mjs';
  const manifest = 'apps/web/src/generated/marketing-product-assets.json';
  const capturedAt = '2026-10-01T12:00:00Z';
  const later = '2026-11-02T12:00:00Z';
  const env = {
    ...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))),
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_AUTHOR_NAME: 'fixture',
    GIT_AUTHOR_EMAIL: 'fixture@example.com',
    GIT_COMMITTER_NAME: 'fixture',
    GIT_COMMITTER_EMAIL: 'fixture@example.com',
  };
  const directories: string[] = [];
  const git = (cwd: string, ...args: string[]) =>
    execFileSync('git', args, { cwd, env, stdio: 'pipe', timeout: 10_000 });
  const readManifest = (cwd: string) => JSON.parse(readFileSync(path.join(cwd, manifest), 'utf8'));
  const sync = (cwd: string) =>
    spawnSync(process.execPath, [script], { cwd, env, encoding: 'utf8', timeout: 10_000 });
  const directory = () => {
    const cwd = mkdtempSync(path.join(tmpdir(), 'lyb-marketing-assets-'));
    directories.push(cwd);
    return cwd;
  };
  const commit = (cwd: string, date: string) => {
    git(cwd, 'add', '.');
    execFileSync('git', ['commit', '-qm', 'fixture'], {
      cwd,
      env: { ...env, GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date },
      stdio: 'pipe',
      timeout: 10_000,
    });
  };
  const fixture = () => {
    const cwd = directory();
    const receipt = structuredClone(productAssets);
    for (const file of [script, ...Object.values(receipt).map((asset) => asset.source)]) {
      mkdirSync(path.dirname(path.join(cwd, file)), { recursive: true });
      copyFileSync(path.join(root, file), path.join(cwd, file));
    }
    for (const asset of Object.values(receipt)) asset.capturedAt = capturedAt;
    mkdirSync(path.dirname(path.join(cwd, manifest)), { recursive: true });
    writeFileSync(path.join(cwd, manifest), JSON.stringify(receipt));
    git(cwd, 'init', '-q');
    commit(cwd, capturedAt);
    writeFileSync(path.join(cwd, 'unrelated.txt'), 'unrelated merge head');
    commit(cwd, later);
    return cwd;
  };

  afterEach(() => {
    for (const cwd of directories.splice(0)) rmSync(cwd, { recursive: true, force: true });
  });

  it('preserves capture age through a depth-one checkout and repeated builds', () => {
    const original = fixture();
    const shallow = directory();
    git(original, 'clone', '-q', '--depth=1', `file://${original}`, shallow);
    for (const cwd of [shallow, original]) {
      expect(sync(cwd).status).toBe(0);
      const first = readFileSync(path.join(cwd, manifest), 'utf8');
      expect(readManifest(cwd).weightLog.capturedAt).toBe(capturedAt);
      expect(sync(cwd).status).toBe(0);
      expect(readFileSync(path.join(cwd, manifest), 'utf8')).toBe(first);
    }
  });

  it('derives a new timestamp only from committed matching bytes with complete history', () => {
    const cwd = fixture();
    const source = path.join(cwd, productAssets.weightLog.source);
    writeFileSync(source, Buffer.concat([readFileSync(source), Buffer.from('changed fixture')]));
    commit(cwd, later);
    expect(sync(cwd).status).toBe(0);
    expect(Date.parse(readManifest(cwd).weightLog.capturedAt)).toBe(Date.parse(later));
    expect(readManifest(cwd).weightLog.sourceSha256).toBe(sha256(source));
    expect(readManifest(cwd).appIcon.capturedAt).toBe(capturedAt);
  });

  it.each(['shallow', 'uncommitted', 'archive', 'invalid-date'])(
    'refuses unsupported capture provenance (%s) without rewriting the receipt',
    (kind) => {
      let cwd = fixture();
      if (kind === 'shallow' || kind === 'uncommitted') {
        const source = path.join(cwd, productAssets.weightLog.source);
        writeFileSync(source, Buffer.concat([readFileSync(source), Buffer.from('new bytes')]));
        if (kind === 'shallow') {
          commit(cwd, later);
          const clone = directory();
          git(cwd, 'clone', '-q', '--depth=1', `file://${cwd}`, clone);
          cwd = clone;
        }
      } else if (kind === 'archive') {
        rmSync(path.join(cwd, '.git'), { recursive: true });
        rmSync(path.join(cwd, manifest));
      } else {
        const receipt = readManifest(cwd);
        receipt.weightLog.capturedAt = 'not a date';
        writeFileSync(path.join(cwd, manifest), JSON.stringify(receipt));
      }
      const before = kind === 'archive' ? null : readFileSync(path.join(cwd, manifest), 'utf8');
      const result = sync(cwd);
      expect(result.status).not.toBe(0);
      expect(result.stderr).toMatch(/capture provenance/i);
      if (before !== null) expect(readFileSync(path.join(cwd, manifest), 'utf8')).toBe(before);
    },
  );
});
