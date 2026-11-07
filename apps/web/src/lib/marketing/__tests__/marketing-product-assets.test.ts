/**
 * @jest-environment node
 */
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
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
  const futureDate = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
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

  it.each(['existing', 'absent'] as const)(
    'validates later asset provenance before publishing any outputs (%s)',
    (outputs) => {
      expect(generate().status).toBe(0);
      const paths = Object.values(productAssets).map((asset) => path.join(root, asset.output));
      if (outputs === 'existing') {
        writeFileSync(paths[0], 'previous public output');
      } else {
        for (const output of paths) rmSync(output);
      }
      const before = paths.map((output) => (existsSync(output) ? sha256(output) : null));
      const recorded = manifest();
      recorded.appIcon.capturedAt = futureDate;
      writeFileSync(path.join(root, manifestPath), JSON.stringify(recorded));
      const receipt = readFileSync(path.join(root, manifestPath), 'utf8');
      rmSync(path.join(root, '.git'), { recursive: true });

      const result = generate();

      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain('capture timestamp');
      expect(readFileSync(path.join(root, manifestPath), 'utf8')).toBe(receipt);
      expect(paths.map((output) => (existsSync(output) ? sha256(output) : null))).toEqual(before);
    },
  );

  it('recovers a future recorded date from complete capture history', () => {
    const recorded = manifest();
    recorded.weightLog.capturedAt = futureDate;
    writeFileSync(path.join(root, manifestPath), JSON.stringify(recorded));
    expect(generate().status).toBe(0);
    expect(Date.parse(manifest().weightLog.capturedAt)).toBe(Date.parse(captureDate));
  });

  it.each(['archive', 'shallow'] as const)(
    'refuses future recorded provenance without complete history (%s)',
    (checkout) => {
      if (checkout === 'shallow') {
        const clone = path.join(directory, 'shallow');
        git('clone', '--quiet', '--depth=1', `file://${root}`, clone);
        root = clone;
      } else {
        rmSync(path.join(root, '.git'), { recursive: true });
      }
      const recorded = manifest();
      recorded.weightLog.capturedAt = futureDate;
      const before = JSON.stringify(recorded);
      writeFileSync(path.join(root, manifestPath), before);
      const result = generate();
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain('capture timestamp');
      expect(readFileSync(path.join(root, manifestPath), 'utf8')).toBe(before);
    },
  );

  it('refuses a future capture commit instead of emitting a future timestamp', () => {
    execFileSync(
      'git',
      [
        '-c',
        'user.name=Fixture',
        '-c',
        'user.email=fixture@example.invalid',
        'commit',
        '--amend',
        '--no-edit',
      ],
      { cwd: root, env: { ...process.env, GIT_COMMITTER_DATE: futureDate } },
    );
    rmSync(path.join(root, manifestPath));
    const result = generate();
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain('capture timestamp');
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

describe('marketing asset sync provenance', () => {
  const root = path.resolve(process.cwd(), '../..');
  const script = 'scripts/marketing/sync-ios-marketing-assets.mjs';
  const manifest = 'apps/web/src/generated/marketing-product-assets.json';
  const capturedAt = '2026-10-01T12:00:00Z';
  const later = '2026-10-02T12:00:00Z';
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
