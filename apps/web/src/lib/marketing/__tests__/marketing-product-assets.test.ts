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

describe('marketing asset capture provenance', () => {
  const repository = path.resolve(process.cwd(), '../..');
  const generator = 'scripts/marketing/sync-ios-marketing-assets.mjs';
  const manifestPath = 'apps/web/src/generated/marketing-product-assets.json';
  const captureDate = '2026-10-21T02:28:23+00:00';
  let directory: string;
  let root: string;

  function git(...args: string[]) {
    return execFileSync('git', args, {
      cwd: root,
      encoding: 'utf8',
      env: {
        ...process.env,
        GIT_AUTHOR_DATE: captureDate,
        GIT_COMMITTER_DATE: captureDate,
      },
    }).trim();
  }

  function generate() {
    return spawnSync(process.execPath, [generator], { cwd: root, encoding: 'utf8' });
  }

  function manifest() {
    return JSON.parse(readFileSync(path.join(root, manifestPath), 'utf8')) as typeof productAssets;
  }

  beforeEach(() => {
    directory = mkdtempSync(path.join(tmpdir(), 'lyb-marketing-provenance-'));
    root = path.join(directory, 'source');
    const recorded = structuredClone(productAssets);
    for (const asset of Object.values(recorded)) {
      mkdirSync(path.dirname(path.join(root, asset.source)), { recursive: true });
      copyFileSync(path.join(repository, asset.source), path.join(root, asset.source));
      asset.capturedAt = captureDate;
    }
    for (const relative of [generator, manifestPath]) {
      mkdirSync(path.dirname(path.join(root, relative)), { recursive: true });
    }
    copyFileSync(path.join(repository, generator), path.join(root, generator));
    writeFileSync(path.join(root, manifestPath), JSON.stringify(recorded));
    git('init', '--quiet');
    git('add', '.');
    git(
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-qm',
      'capture',
    );
  });

  afterEach(() => rmSync(directory, { recursive: true, force: true }));

  it('preserves hash-bound capture dates in a shallow synthetic merge checkout', () => {
    git('switch', '-qc', 'other');
    writeFileSync(path.join(root, 'other.txt'), 'unrelated branch');
    git('add', '.');
    git(
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-qm',
      'other',
    );
    git('switch', '-qc', 'queue', 'HEAD~1');
    writeFileSync(path.join(root, 'queue.txt'), 'unrelated queue');
    git('add', '.');
    git(
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-qm',
      'queue',
    );
    execFileSync(
      'git',
      [
        '-c',
        'user.name=Fixture',
        '-c',
        'user.email=fixture@example.invalid',
        'merge',
        '--no-ff',
        '-qm',
        'synthetic merge',
        'other',
      ],
      {
        cwd: root,
        env: {
          ...process.env,
          GIT_AUTHOR_DATE: '2030-01-01T00:00:00Z',
          GIT_COMMITTER_DATE: '2030-01-01T00:00:00Z',
        },
      },
    );
    const clone = path.join(directory, 'shallow');
    git('clone', '--quiet', '--depth=1', `file://${root}`, clone);
    root = clone;
    expect(git('rev-parse', '--is-shallow-repository')).toBe('true');
    expect(generate().status).toBe(0);
    expect(manifest().weightLog.capturedAt).toBe(captureDate);
    expect(generate().status).toBe(0);
    expect(manifest().weightLog.capturedAt).toBe(captureDate);
  });

  it('retains recorded capture dates in source archives instead of using extraction time', () => {
    rmSync(path.join(root, '.git'), { recursive: true });
    expect(generate().status).toBe(0);
    expect(manifest().weightLog.capturedAt).toBe(captureDate);
  });

  it.each([captureDate, '2026-10-21T02:28:23Z', '2026-10-20T19:28:23-07:00'])(
    'derives the exact capture instant from complete history (%s)',
    (expectedCaptureDate) => {
      rmSync(path.join(root, manifestPath));
      expect(generate().status).toBe(0);
      expect(Date.parse(manifest().weightLog.capturedAt)).toBe(Date.parse(expectedCaptureDate));
    },
  );

  it('refuses a shallow boundary without matching recorded evidence', () => {
    const clone = path.join(directory, 'shallow');
    git('clone', '--quiet', '--depth=1', `file://${root}`, clone);
    root = clone;
    const recorded = manifest();
    recorded.weightLog.sourceSha256 = '0'.repeat(64);
    const before = JSON.stringify(recorded);
    writeFileSync(path.join(root, manifestPath), before);
    expect(generate().stderr).toContain('capture timestamp');
    expect(readFileSync(path.join(root, manifestPath), 'utf8')).toBe(before);
  });

  it('refuses uncommitted bytes instead of assigning the previous capture date', () => {
    rmSync(path.join(root, manifestPath));
    const source = path.join(root, productAssets.weightLog.source);
    writeFileSync(source, Buffer.concat([readFileSync(source), Buffer.from('changed')]));
    const result = generate();
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain('capture timestamp');
  });

  it.each(['hash', 'date', 'missing'] as const)(
    'refuses unavailable capture evidence (%s) without refreshing freshness or writing the manifest',
    (invalid) => {
      const recorded = manifest();
      if (invalid === 'hash') recorded.weightLog.sourceSha256 = '0'.repeat(64);
      if (invalid === 'date') recorded.weightLog.capturedAt = 'invalid';
      writeFileSync(path.join(root, manifestPath), JSON.stringify(recorded));
      if (invalid === 'missing') rmSync(path.join(root, manifestPath));
      const before =
        invalid === 'missing' ? null : readFileSync(path.join(root, manifestPath), 'utf8');
      rmSync(path.join(root, '.git'), { recursive: true });
      const result = generate();
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain('capture timestamp');
      if (before !== null) expect(readFileSync(path.join(root, manifestPath), 'utf8')).toBe(before);
    },
  );
});
