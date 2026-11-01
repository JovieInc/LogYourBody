import { render } from '@testing-library/react';
import HomePage from '../page';
import robots from '../robots';
import sitemap from '../sitemap';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import { endpoints } from '@/lib/generated/endpoints.generated';
import { PUBLIC_MARKETING_ROUTES } from '@/data/publicMarketingRoutes';
import { getAllPosts } from '@/lib/blog';

jest.mock('@/lib/blog', () => ({ getAllPosts: jest.fn().mockResolvedValue([]) }));

jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: { ART_DIRECTION_V2_ENABLED: false, APP_STORE_LIVE: false },
}));
jest.mock('@/lib/flags/publicLanding.server', () => ({
  readEditorialHomepageRollout: jest.fn().mockResolvedValue(true),
}));

jest.mock('@/lib/analytics', () => ({
  analytics: { track: jest.fn() },
}));

jest.mock('../MinimalWaitlistLanding', () => ({
  MinimalWaitlistLanding: () => <main data-testid="minimal-landing" />,
}));

jest.mock('../LegacyMinimalWaitlistLanding', () => ({
  LegacyMinimalWaitlistLanding: () => <main data-testid="legacy-minimal-landing" />,
}));

describe('marketing discovery routes', () => {
  it('publishes a nonempty robots policy and sitemap URL', () => {
    const value = robots();
    expect(value.host).toBe('https://www.logyourbody.com');
    expect(value.sitemap).toBe('https://www.logyourbody.com/sitemap.xml');
    expect(value.rules).toEqual(expect.objectContaining({ userAgent: '*', allow: '/' }));
  });

  it('keeps legacy auth redirects out of search results (LYB-100)', () => {
    expect(robots().rules).toEqual(
      expect.objectContaining({ disallow: expect.arrayContaining(['/signin', '/signup']) }),
    );
  });

  it('lists the shared public marketing routes on the canonical host when no posts are published', async () => {
    const urls = (await sitemap()).map((entry) => entry.url);
    expect(urls).toEqual(
      PUBLIC_MARKETING_ROUTES.map((route) => new URL(route, endpoints.hosts.marketing.url).href),
    );
    expect(new Set(urls).size).toBe(urls.length);
    expect(urls.some((url) => url.includes('/dashboard'))).toBe(false);
  });

  it('includes published article URLs with safely encoded slugs', async () => {
    jest.mocked(getAllPosts).mockResolvedValueOnce([
      { slug: 'progress & context', date: '2026-10-14' },
      { slug: 'understand-your-trend', date: '2026-10-15' },
    ] as Awaited<ReturnType<typeof getAllPosts>>);
    const entries = await sitemap();
    expect(entries.slice(-2).map((entry) => entry.url)).toEqual([
      'https://www.logyourbody.com/blog/progress%20%26%20context',
      'https://www.logyourbody.com/blog/understand-your-trend',
    ]);
    // A publication date is not evidence of when an article was last modified.
    for (const entry of entries) expect(entry).not.toHaveProperty('lastModified');
  });

  it('omits modification dates until content or build timestamps are available', async () => {
    for (const entry of await sitemap()) expect(entry).not.toHaveProperty('lastModified');
  });

  it.each([false, true])('emits verified structured data with editorial=%p', async (editorial) => {
    (LANDING_FLAGS as { ART_DIRECTION_V2_ENABLED: boolean }).ART_DIRECTION_V2_ENABLED = editorial;
    const { container } = render(await HomePage());
    const script = container.querySelector('script[type="application/ld+json"]');
    expect(script).not.toBeNull();

    const data = JSON.parse(script?.textContent ?? '{}') as {
      '@graph'?: Array<{ '@type': string }>;
    };
    expect(data['@graph']?.map((entry) => entry['@type'])).toEqual([
      'Organization',
      'WebSite',
      'SoftwareApplication',
    ]);
  });
});
