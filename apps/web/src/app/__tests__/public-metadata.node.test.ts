/** @jest-environment node */

import { existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import type { Metadata } from 'next';
import { accumulateMetadata } from 'next/dist/lib/metadata/resolve-metadata';
import { logYourBody } from '@jovieinc/product-registry';
import nextConfig from '../../../next.config';
import {
  getRedirectUrl,
  unstable_getResponseFromNextConfig,
} from 'next/experimental/testing/server';

jest.mock('server-only', () => ({}));
jest.mock('next/font/local', () => () => ({ variable: '' }));
jest.mock('@vercel/analytics/next', () => ({ Analytics: () => null }));
jest.mock('@vercel/speed-insights/next', () => ({ SpeedInsights: () => null }));
jest.mock('../providers', () => ({ Providers: () => null }));
jest.mock('@/components/PWAInstallPrompt', () => ({ PWAInstallPrompt: () => null }));
jest.mock('@/components/ServiceWorkerUpdater', () => ({ ServiceWorkerUpdater: () => null }));
jest.mock('@/components/MarketingPage', () => ({ MarketingPage: () => null }));
jest.mock('@/components/MarkdownRenderer', () => ({ MarkdownRenderer: () => null }));
jest.mock('@/lib/ports/auth-ui', () => ({}));
jest.mock('../LaunchLanding', () => ({ LaunchLanding: () => null }));
jest.mock('@/lib/flags/publicLanding.server', () => ({}));
jest.mock('@/lib/blog', () => ({
  getAllSlugs: async () => ['first-article', 'second-article'],
  getAllTags: async () => ['Body Composition', 'Training & Recovery'],
  getPostBySlug: async (slug: string) => ({ title: `Article ${slug}`, excerpt: 'An article.' }),
}));

const appDirectory = path.resolve(__dirname, '..');
// LYB-100 app routes are outside this public-site change. New public pages are discovered below.
const appRoots = new Set([
  'api',
  'dashboard',
  'import',
  'log',
  'onboarding',
  'photos',
  'settings',
  'steps',
  'training',
]);
const redirectRoutes = new Set(['/download', '/landing', '/mobile']);
const canonicalAliases: Record<string, string> = { '/download/ios': '/' };

type RouteModule = {
  metadata?: Metadata;
  generateStaticParams?: () => Promise<Record<string, string>[]>;
  generateMetadata?: (props: { params: Promise<Record<string, string>> }) => Promise<Metadata>;
};

function discoverPages(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return entry.name === '__tests__' || (directory === appDirectory && appRoots.has(entry.name))
        ? []
        : discoverPages(filename);
    }
    return entry.name === 'page.tsx' ? [filename] : [];
  });
}

const pages = discoverPages(appDirectory)
  .map((filename) => ({
    filename,
    route:
      '/' +
      path.relative(appDirectory, path.dirname(filename)).split(path.sep).filter(Boolean).join('/'),
  }))
  .filter(({ route }) => !redirectRoutes.has(route));

describe('public route metadata (LYB-223)', () => {
  it('uses the serving www host and permanently redirects the apex while preserving the path', async () => {
    expect(new URL(logYourBody.links.home).hostname).toBe(`www.${logYourBody.identity.domain}`);
    expect(logYourBody.endpoints.hosts.marketing.url).toBe(logYourBody.links.home);
    expect(await nextConfig.redirects?.()).toContainEqual({
      source: '/:path*',
      has: [{ type: 'host', value: logYourBody.identity.domain }],
      destination: `${logYourBody.links.home}/:path*`,
      permanent: true,
    });
  });

  it('does not let public pages inherit a homepage canonical from the root layout', () => {
    expect(require('../layout').metadata.alternates?.canonical).toBeUndefined();
  });

  it.each(['/', '/security', '/privacy?source=search', '/blog/example'])(
    'redirects apex %s with HTTP 308',
    async (pathname) => {
      const response = await unstable_getResponseFromNextConfig({
        url: `https://${logYourBody.identity.domain}${pathname}`,
        nextConfig,
      });
      expect(response.status).toBe(308);
      expect(getRedirectUrl(response)).toBe(`${logYourBody.links.home}${pathname}`);
      const servingResponse = await unstable_getResponseFromNextConfig({
        url: `${logYourBody.links.home}${pathname}`,
        nextConfig,
      });
      expect(getRedirectUrl(servingResponse)).toBeNull();
    },
  );

  it.each(pages)(
    '$route resolves to its own canonical and a distinct title',
    async ({ filename, route }) => {
      const page: RouteModule = require(filename);
      const cases = page.generateStaticParams ? await page.generateStaticParams() : [{}];
      expect(cases.length).toBeGreaterThan(0);
      for (const params of cases) {
        const pathname = route.replace(/\[([^\]]+)\]/g, (_, key: string) =>
          encodeURIComponent(params[key]),
        );
        const directories = path
          .relative(appDirectory, path.dirname(filename))
          .split(path.sep)
          .filter(Boolean);
        const layouts: Array<Metadata | null> = [];
        let directory = appDirectory;
        for (const segment of ['', ...directories]) {
          directory = path.join(directory, segment);
          const layout = path.join(directory, 'layout.tsx');
          layouts.push(existsSync(layout) ? (require(layout).metadata ?? null) : null);
        }
        const metadata = page.generateMetadata
          ? await page.generateMetadata({ params: Promise.resolve(params) })
          : (page.metadata ?? null);
        // Use Next's actual inheritance and title-template resolver, including nested layouts.
        const resolved = await accumulateMetadata(
          pathname,
          [...layouts, metadata].map((value) => [value, null]),
          Promise.resolve(pathname),
          { trailingSlash: false, isStaticMetadataRouteFile: false },
        );
        expect(new URL(resolved.alternates?.canonical?.url?.toString() ?? '').href).toBe(
          new URL(canonicalAliases[pathname] ?? pathname, logYourBody.links.home).href,
        );
        const title = resolved.title?.absolute ?? '';
        expect(title).not.toBe('');
        expect(title.split(logYourBody.identity.name)).toHaveLength(2);
        if (pathname !== '/') {
          expect(title).not.toBe(`${logYourBody.identity.name} — ${logYourBody.brand.slogan}`);
        }
      }
    },
  );
});
