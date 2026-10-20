import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { describe, expect, it } from 'vitest';

const workflow = readFileSync(
  new URL('../../../.github/workflows/security-scan.yml', import.meta.url),
  'utf8',
);
const step =
  workflow.split('    - name: Run Gitleaks\n')[1]?.split('\n  dependency-review:')[0] ?? '';
const run = step
  .split('      run: |\n')[1]
  ?.split('\n')
  .map((line) => line.replace(/^ {8}/, ''))
  .join('\n');
const pinnedUrl =
  'https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz';
const pinnedSha = '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb';

function execute(
  options: { downloadExit?: number; checksumExit?: number; scanExit?: number } = {},
) {
  if (!run) throw new Error('Expected the standalone Gitleaks shell step');
  const directory = mkdtempSync(tmpdir() + '/lyb-gitleaks-step-');
  const putExecutable = (name: string, content: string) => {
    writeFileSync(directory + '/' + name, '#!/bin/bash\nset -eu\n' + content + '\n');
    chmodSync(directory + '/' + name, 0o755);
  };
  const read = (name: string) =>
    existsSync(directory + '/' + name) ? readFileSync(directory + '/' + name, 'utf8') : null;
  try {
    putExecutable(
      'curl',
      'printf "%s\\n" "$@" > "$TEST_DIRECTORY/download-args"\nexit "$DOWNLOAD_EXIT"',
    );
    putExecutable(
      'sha256sum',
      'printf "%s\\n" "$@" > "$TEST_DIRECTORY/checksum-args"\ncat > "$TEST_DIRECTORY/checksum-input"\nexit "$CHECKSUM_EXIT"',
    );
    putExecutable(
      'tar',
      'printf "%s\\n" "$@" > "$TEST_DIRECTORY/tar-args"\nwhile [ "$#" -gt 0 ]; do\n  if [ "$1" = "-C" ]; then cp "$TEST_DIRECTORY/scanner" "$2/gitleaks"; break; fi\n  shift\ndone',
    );
    putExecutable(
      'scanner',
      'printf "%s\\n" "$@" > "$TEST_DIRECTORY/scan-args"\nexit "$SCAN_EXIT"',
    );
    const result = spawnSync('/bin/bash', ['-e', '-o', 'pipefail', '-c', run], {
      encoding: 'utf8',
      timeout: 10_000,
      env: {
        ...process.env,
        PATH: directory + ':/usr/bin:/bin',
        RUNNER_TEMP: directory,
        TEST_DIRECTORY: directory,
        GITLEAKS_ARCHIVE_URL: step.match(/GITLEAKS_ARCHIVE_URL: ['"]?([^'"\s]+)/)?.[1],
        GITLEAKS_SHA256: step.match(/GITLEAKS_SHA256: ['"]?([^'"\s]+)/)?.[1],
        DOWNLOAD_EXIT: String(options.downloadExit ?? 0),
        CHECKSUM_EXIT: String(options.checksumExit ?? 0),
        SCAN_EXIT: String(options.scanExit ?? 0),
      },
    });
    return {
      status: result.status,
      stderr: result.stderr,
      downloadArgs: read('download-args'),
      checksumArgs: read('checksum-args'),
      checksumInput: read('checksum-input'),
      tarArgs: read('tar-args'),
      scanArgs: read('scan-args')?.trim().split('\n'),
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

// Allow the bounded 10-second shell process to finish and clean up under parallel CI load.
describe('standalone Gitleaks security gate', () => {
  it('verifies the official pinned archive before scanning all fetched history with full redaction', () => {
    expect(workflow).toContain('name: Secret Leak Detection');
    expect(workflow).toMatch(/fetch-depth: 0/);
    expect(step).not.toContain('gitleaks-action');
    expect(step).not.toContain('GITLEAKS_LICENSE');
    const result = execute();
    expect(result.status).toBe(0);
    expect(result.downloadArgs).toContain(pinnedUrl);
    expect(result.checksumArgs).toBe('--check\n--strict\n');
    expect(result.checksumInput).toMatch(
      new RegExp('^' + pinnedSha + '  .+/gitleaks\\.tar\\.gz\\n$'),
    );
    expect(result.scanArgs).toEqual([
      'git',
      '--log-opts=--all',
      '--redact=100',
      '--exit-code=1',
      '--no-banner',
      '--no-color',
      '.',
    ]);
  }, 15_000);

  it.each([1, 2])(
    'propagates scanner exit %s instead of making the security gate green',
    (scanExit) => {
      expect(execute({ scanExit }).status).toBe(scanExit);
    },
    15_000,
  );

  it('does not extract or execute an archive whose checksum fails', () => {
    const result = execute({ checksumExit: 1 });
    expect(result.status).toBe(1);
    expect(result.tarArgs).toBeNull();
    expect(result.scanArgs).toBeUndefined();
  }, 15_000);

  it('does not verify, extract or execute a failed download', () => {
    const result = execute({ downloadExit: 22 });
    expect(result.status).toBe(22);
    expect(result.checksumInput).toBeNull();
    expect(result.tarArgs).toBeNull();
    expect(result.scanArgs).toBeUndefined();
  }, 15_000);
});
