import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = new URL('../../..', import.meta.url);
const webAppRouteDir = new URL('../../../apps/web/src/app/', import.meta.url);

function listFiles(dir: string): string[] {
  if (!existsSync(dir)) {
    return [];
  }

  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = join(dir, entry.name);

    if (entry.isDirectory()) {
      return listFiles(fullPath);
    }

    return entry.isFile() ? [relative(fileURLToPath(repoRoot), fullPath)] : [];
  });
}

describe('web surface cleanup', () => {
  it('uses the ESLint CLI instead of next lint', () => {
    const packageJson = JSON.parse(
      readFileSync(new URL('../../../apps/web/package.json', import.meta.url), 'utf8'),
    );

    expect(packageJson.scripts.lint).toBe('eslint src');
    expect(JSON.stringify(packageJson.scripts)).not.toContain('next lint');
  });

  it('keeps pnpm overrides at workspace scope', () => {
    const workspaceConfig = readFileSync(
      new URL('../../../pnpm-workspace.yaml', import.meta.url),
      'utf8',
    );
    const packageJson = JSON.parse(
      readFileSync(new URL('../../../apps/web/package.json', import.meta.url), 'utf8'),
    );

    expect(packageJson.pnpm).toBeUndefined();
    expect(workspaceConfig).toContain('overrides:');
    expect(workspaceConfig).toContain('js-yaml: 4.1.1');
    expect(workspaceConfig).toContain('prismjs: 1.30.0');
  });

  it('does not ship debug or test route entry files', () => {
    const routeFiles = listFiles(fileURLToPath(webAppRouteDir))
      .filter((filePath) => filePath.endsWith('/page.tsx') || filePath.endsWith('/route.ts'))
      .map((filePath) => filePath.replace(/^apps\/web\/src\/app\//, ''));

    expect(routeFiles).not.toEqual(
      expect.arrayContaining([
        'api/debug/route.ts',
        'api/debug/auth/route.ts',
        'api/debug-pdf/route.ts',
        'api/test-openai/route.ts',
        'debug/page.tsx',
        'debug-auth/page.tsx',
        'debug-login/page.tsx',
        'test/page.tsx',
        'test-login/page.tsx',
        'test-sms/page.tsx',
        'pwa-test/page.tsx',
      ]),
    );
  });

  it('keeps tracked public test artifacts out of the web app', () => {
    expect(existsSync(new URL('../../../apps/web/public/test-login.html', import.meta.url))).toBe(
      false,
    );
  });
});
