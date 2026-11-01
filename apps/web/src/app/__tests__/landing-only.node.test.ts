/** @jest-environment node */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { PUBLIC_MARKETING_ROUTES } from '@/data/publicMarketingRoutes';
import nextConfig from '../../../next.config';
import { unstable_getResponseFromNextConfig } from 'next/experimental/testing/server';

const appRoot = join(process.cwd(), 'src/app');
const retiredRoutes = [
  '/dashboard',
  '/log',
  '/photos',
  '/settings',
  '/onboarding',
  '/steps',
  '/import',
  '/training',
];
const publicRoutes = new Set<string>([
  ...PUBLIC_MARKETING_ROUTES,
  '/download',
  '/landing',
  '/mobile',
  '/signin',
  '/signup',
  '/blog/[slug]',
  '/blog/tag/[tag]',
]);

function filesIn(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name === '__tests__') return [];
    const path = join(directory, entry.name);
    return entry.isDirectory() ? filesIn(path) : [path];
  });
}

describe('lyb-web-landing-only-v1 (LYB-100)', () => {
  it('exposes only marketing, legal and API-support authentication pages', () => {
    const routes = filesIn(appRoot)
      .filter((path) => /[\\/]page\.[jt]sx?$/.test(path))
      .map(
        (path) =>
          '/' +
          relative(appRoot, path)
            .split('/')
            .slice(0, -1)
            .filter((part) => !part.startsWith('(') && !part.startsWith('@'))
            .join('/'),
      );
    expect(routes.filter((route) => !publicRoutes.has(route))).toEqual([]);
    for (const route of PUBLIC_MARKETING_ROUTES) {
      expect(routes).toContain(route);
    }
  });

  it.each(retiredRoutes)('sends legacy %s URLs to the iPhone download page', async (route) => {
    for (const suffix of ['', '/', '/nested?from=bookmark']) {
      let url = `https://www.logyourbody.com${route}${suffix}`;
      // Next normalizes a trailing slash before applying configured redirects.
      for (let hop = 0; hop < 3 && new URL(url).pathname !== '/download/ios'; hop++) {
        const response = await unstable_getResponseFromNextConfig({ url, nextConfig });
        expect(response.status).toBe(308);
        url = new URL(response.headers.get('location')!, url).href;
      }
      expect(new URL(url).pathname).toBe('/download/ios');
    }
  });

  it.each([
    '/',
    '/security',
    '/privacy',
    '/terms',
    '/blog',
    '/api/auth/mobile/sync/v1/body-metrics',
    '/api/training/canvas',
    '/api/parse-pdf',
    '/logging',
    '/settings-help',
  ])('does not redirect the unrelated path %s', async (route) => {
    const response = await unstable_getResponseFromNextConfig({
      url: `https://www.logyourbody.com${route}`,
      nextConfig,
    });
    expect(response.headers.get('location')).toBeNull();
  });

  it('removes app navigation and keeps manifest shortcuts on public pages', () => {
    expect(existsSync(join(process.cwd(), 'src/components/MobileNavbar.tsx'))).toBe(false);
    const manifest = JSON.parse(
      readFileSync(join(process.cwd(), 'public/site.webmanifest'), 'utf8'),
    );
    for (const shortcut of manifest.shortcuts ?? []) {
      expect(publicRoutes.has(shortcut.url)).toBe(true);
    }
    const sources = filesIn(join(process.cwd(), 'src')).filter(
      (path) =>
        /\.[jt]sx?$/.test(path) && !/\.(test|spec)\./.test(path) && !path.includes('/app/api/'),
    );
    const deadLinks = sources.flatMap((path) => {
      const source = readFileSync(path, 'utf8');
      return retiredRoutes.flatMap((route) => {
        const pattern = new RegExp(
          `(?:href\\s*[:=]\\s*|(?:push|replace|redirect)\\(\\s*)["']${route}(?:[/'"?#])`,
        );
        return pattern.test(source) ? [relative(process.cwd(), path)] : [];
      });
    });
    expect(deadLinks).toEqual([]);
  });
});
