import { describe, expect, it } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const root = resolve(__dirname, '../../..');
const configs = ['vercel.json', 'apps/web/vercel.json'];

describe('Vercel package manager routing', () => {
  for (const config of configs) {
    it(`${config} bypasses a shadow pnpm and preserves frozen installation`, () => {
      const dir = mkdtempSync(join(tmpdir(), 'lyb-pnpm-route-'));
      try {
        const log = join(dir, 'calls');
        writeFileSync(join(dir, 'pnpm'), '#!/bin/sh\nexit 97\n', { mode: 0o755 });
        writeFileSync(join(dir, 'corepack'), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\n', {
          mode: 0o755,
        });
        const { installCommand, buildCommand } = JSON.parse(
          readFileSync(join(root, config), 'utf8'),
        );
        const env = { ...process.env, PATH: `${dir}:${process.env.PATH}`, CALL_LOG: log };
        execFileSync('/bin/sh', ['-c', installCommand], { env });
        execFileSync('/bin/sh', ['-c', buildCommand], { env });
        const calls = readFileSync(log, 'utf8').trim().split('\n');
        expect(calls[0]).toBe('pnpm --version');
        expect(calls[1]).toBe('pnpm install --frozen-lockfile');
        expect(calls[2]).toMatch(/^pnpm .*build$/);
        writeFileSync(join(dir, 'corepack'), '#!/bin/sh\nexit 42\n', { mode: 0o755 });
        expect(spawnSync('/bin/sh', ['-c', installCommand], { env }).status).toBe(42);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });
  }
});
