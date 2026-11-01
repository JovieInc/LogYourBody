import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ESLint } from 'eslint';
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
  it('enforces lyb-web-landing-only-v1 for every mounted web page', () => {
    const publicPages = listFiles(fileURLToPath(webAppRouteDir))
      .filter((path) => /\/page\.(?:[jt]sx?)$/.test(path))
      .map((path) => path.replace(/^apps\/web\/src\/app\//, '').replace(/\/page\.[jt]sx?$/, ''));

    expect(publicPages.sort()).toEqual(
      [
        'about',
        'blog',
        'blog/[slug]',
        'blog/tag/[tag]',
        'brand',
        'careers',
        'changelog',
        'consumer-health-data',
        'delete-account',
        'download',
        'download/android',
        'download/ios',
        'health-disclosure',
        'landing',
        'mobile',
        'page.tsx',
        'privacy',
        'security',
        'signin',
        'signup',
        'support',
        'terms',
      ].sort(),
    );
  });

  it('keeps production navigation free of links to retired app routes', () => {
    const deadLinks = listFiles(fileURLToPath(new URL('../../../apps/web/src/', import.meta.url)))
      .filter((path) => /\.[jt]sx?$/.test(path) && !/(?:__tests__|\.(?:test|spec)\.)/.test(path))
      .flatMap((path) => {
        const source = readFileSync(new URL(path, repoRoot), 'utf8');
        const links = source.match(
          /(?:href\s*[:=]\s*\{?\s*|router\.(?:push|replace)\(\s*)['"`]\/(?:dashboard|log|photos|settings|onboarding|steps|import|training)(?:[/'"`?#])/g,
        );
        return links ? [{ path, links }] : [];
      });
    expect(deadLinks).toEqual([]);
  });

  it('removes product navigation and installed web-app shortcuts', () => {
    expect(
      existsSync(new URL('../../../apps/web/src/components/MobileNavbar.tsx', import.meta.url)),
    ).toBe(false);
    const manifest = JSON.parse(
      readFileSync(new URL('../../../apps/web/public/site.webmanifest', import.meta.url), 'utf8'),
    );
    expect(manifest.shortcuts ?? []).toEqual([]);
  });

  it('retires the unused store redirect and unpublished Android listing', () => {
    expect(existsSync(new URL('api/app-store-redirect/route.ts', webAppRouteDir))).toBe(false);
    expect(
      readFileSync(new URL('../../../apps/web/src/constants/app.ts', import.meta.url), 'utf8'),
    ).not.toContain('playStoreUrl');
  });

  it.each(['src/app/api/example/route.ts', 'src/app/example/route.ts'])(
    'rejects console.log in public route handler %s',
    async (filePath) => {
      const eslint = new ESLint({
        cwd: fileURLToPath(new URL('../../../apps/web/', import.meta.url)),
      });

      for (const source of ["console.log('hit');", "console['log']('hit');"]) {
        const [result] = await eslint.lintText(source, { filePath });
        expect(result.messages).toEqual(
          expect.arrayContaining([expect.objectContaining({ ruleId: 'no-console', severity: 2 })]),
        );
      }

      const [result] = await eslint.lintText(
        "console.warn('warning'); console.error('failure'); console.info('stream outcome');",
        { filePath },
      );
      expect(result.errorCount).toBe(0);
    },
  );

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
    expect(workspaceConfig).toContain('js-yaml: 5.4.3');
    expect(workspaceConfig).toContain('prismjs: 1.30.0');
    expect(workspaceConfig).toContain('source-map-js: 1.2.2');
    expect(workspaceConfig).toContain('postcss-selector-parser: 7.1.6');
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
