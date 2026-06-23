import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));

describe('vendor boundary guard', () => {
  it('keeps direct vendor SDK imports inside approved adapter/service boundaries', () => {
    expect(() => {
      execFileSync('node', ['scripts/check-vendor-boundaries.js'], {
        cwd: repoRoot,
        stdio: 'pipe',
      });
    }).not.toThrow();
  });
});
