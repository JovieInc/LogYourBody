/** @jest-environment node */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import type { Metadata } from 'next';
import { logYourBody } from '@jovieinc/product-registry';
import { PUBLIC_MARKETING_ROUTES } from '@/data/publicMarketingRoutes';
import { getAllTags, getPostBySlug } from '@/lib/blog';
import {
  getRedirectUrl,
  unstable_getResponseFromNextConfig,
} from 'next/experimental/testing/server';
import nextConfig from '../../../next.config';
import { accumulateMetadata, type MetadataItems } from 'next/dist/lib/metadata/resolve-metadata';

jest.mock('server-only', () => ({}));
jest.mock('next/navigation', () => ({ notFound: jest.requireActual('next/navigation').notFound }));
jest.mock('next/font/local', () => () => ({ variable: 'font' }));
jest.mock('@vercel/analytics/next', () => ({ Analytics: () => null }));
jest.mock('@vercel/speed-insights/next', () => ({ SpeedInsights: () => null }));
jest.mock('@/app/providers', () => ({ Providers: () => null }));
jest.mock('@/components/PWAInstallPrompt', () => ({ PWAInstallPrompt: () => null }));
jest.mock('@/components/ServiceWorkerUpdater', () => ({ ServiceWorkerUpdater: () => null }));
jest.mock('@/components/MarketingPage', () => ({ MarketingPage: () => null }));
jest.mock('@/components/MarkdownRenderer', () => ({ MarkdownRenderer: () => null }));
jest.mock('@/app/LaunchLanding', () => ({ LaunchLanding: () => null }));
jest.mock('@/lib/flags/publicLanding.server', () => ({ readEditorialHomepageRollout: jest.fn() }));
jest.mock('@/lib/blog', () => ({ getAllTags: jest.fn(), getPostBySlug: jest.fn() }));

const appRoot = path.join(process.cwd(), 'src/app');
// Redirect-only acquisition routes emit no indexable document.
const aliases: Record<string, string> = { '/download/ios': '/' };
const redirectPages = ['download/page.tsx', 'landing/page.tsx', 'mobile/page.tsx'];

function publicPages(directory = appRoot): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    const relative = path.relative(appRoot, file);
    if (entry.isDirectory()) {
      if (entry.name === '__tests__' || relative.split(path.sep)[0] === 'api') return [];
      return publicPages(file);
    }
    if (!/^page\.[jt]sx?$/.test(entry.name)) return [];
    if (redirectPages.includes(relative) && /\bredirect\(/.test(readFileSync(file, 'utf8')))
      return [];
    return [relative];
  });
}

const { metadata: rootMetadata } = require('../layout') as { metadata: Metadata };
const base = new URL(String(rootMetadata.metadataBase));

async function assertMetadata(metadata: Metadata, route: string) {
  expect(metadata.title).toBeTruthy();
  const items: MetadataItems = [[rootMetadata, null]];
  const segments = route.split('/').filter(Boolean);
  for (let depth = 1; depth <= segments.length; depth++) {
    const layout = path.join(appRoot, ...segments.slice(0, depth), 'layout.tsx');
    items.push([existsSync(layout) ? (require(layout).metadata ?? null) : null, null]);
  }
  items.push([metadata, null]);
  // Use Next's resolver so nested layout templates and metadata inheritance are exercised.
  const resolved = await accumulateMetadata(route, items, Promise.resolve(route), {
    trailingSlash: false,
    isStaticMetadataRouteFile: false,
  });
  expect(new URL(String(resolved.alternates?.canonical?.url)).href).toBe(
    new URL(aliases[route] ?? route, base).href,
  );
  expect(resolved.title?.absolute.split(logYourBody.identity.name)).toHaveLength(2);
  if (route !== '/') {
    expect(resolved.title?.absolute).not.toBe(
      `${logYourBody.identity.name} — ${logYourBody.brand.slogan}`,
    );
  }
}

describe('public route metadata contract (LYB-223)', () => {
  it.each(['/', '/security', '/blog/progress?source=search'])(
    'permanently redirects the apex while preserving %s',
    async (route) => {
      const response = await unstable_getResponseFromNextConfig({
        url: `https://${logYourBody.identity.domain}${route}`,
        nextConfig,
      });
      expect(response.status).toBe(308);
      expect(getRedirectUrl(response)).toBe(`${logYourBody.links.home}${route}`);
      const servingResponse = await unstable_getResponseFromNextConfig({
        url: `${logYourBody.links.home}${route}`,
        nextConfig,
      });
      expect(getRedirectUrl(servingResponse)).toBeNull();
    },
  );

  it('uses the serving www host and does not inherit a homepage canonical', () => {
    expect(base.origin).toBe('https://www.logyourbody.com');
    expect(logYourBody.endpoints.hosts.marketing.url).toBe(base.origin);
    expect(rootMetadata.alternates?.canonical).toBeUndefined();
  });

  it('enforces the landing-only route inventory (LYB-100)', () => {
    const routes = publicPages()
      .filter((file) => !file.includes('['))
      .map((file) => '/' + path.dirname(file).replace(/^\.$/, '').split(path.sep).join('/'));
    expect([...PUBLIC_MARKETING_ROUTES].sort()).toEqual(routes.sort());
  });

  it.each(publicPages().filter((file) => !file.includes('[')))(
    '%s has its own canonical and title',
    async (file) => {
      const route = '/' + path.dirname(file).replace(/^\.$/, '').split(path.sep).join('/');
      const { metadata } = require(path.join(appRoot, file)) as { metadata: Metadata };
      expect(metadata).toBeDefined();
      await assertMetadata(metadata, route);
    },
  );

  it('requires metadata coverage for every dynamic public route', () => {
    expect(
      publicPages()
        .filter((file) => file.includes('['))
        .sort(),
    ).toEqual(['blog/[slug]/page.tsx', 'blog/tag/[tag]/page.tsx']);
  });

  it('canonicalizes each published article to its own encoded path', async () => {
    jest.mocked(getPostBySlug).mockResolvedValue({
      slug: 'progress-trends',
      title: 'Progress trends',
      excerpt: 'Trend context.',
    } as Awaited<ReturnType<typeof getPostBySlug>>);
    const { generateMetadata } = require('../blog/[slug]/page');
    await assertMetadata(
      await generateMetadata({ params: Promise.resolve({ slug: 'progress-trends' }) }),
      '/blog/progress-trends',
    );
    jest.mocked(getPostBySlug).mockResolvedValue(null);
    await expect(
      generateMetadata({ params: Promise.resolve({ slug: 'unpublished' }) }),
    ).rejects.toThrow();
  });

  it('canonicalizes tag pages and withholds unknown tags', async () => {
    jest.mocked(getAllTags).mockResolvedValue(['Progress Tracking', 'Training & Recovery']);
    const { generateMetadata } = require('../blog/tag/[tag]/page');
    for (const tag of ['progress-tracking', 'training-&-recovery']) {
      await assertMetadata(
        await generateMetadata({ params: Promise.resolve({ tag }) }),
        `/blog/tag/${encodeURIComponent(tag)}`,
      );
    }
    await expect(
      generateMetadata({ params: Promise.resolve({ tag: 'unknown' }) }),
    ).rejects.toThrow();
  });
});
