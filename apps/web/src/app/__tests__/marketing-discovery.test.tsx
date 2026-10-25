import { render } from '@testing-library/react';
import HomePage from '../page';
import robots from '../robots';
import sitemap from '../sitemap';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import { PUBLIC_MARKETING_ROUTES } from '@/data/publicMarketingRoutes';
import { endpoints } from '@/lib/generated/endpoints.generated';

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
    expect(value.sitemap).toBe('https://www.logyourbody.com/sitemap.xml');
    expect(value.host).toBe(endpoints.hosts.marketing.url);
    expect(value.rules).toEqual(expect.objectContaining({ userAgent: '*', allow: '/' }));
  });

  it('sitemap equals the public marketing route list on the canonical host', () => {
    const urls = sitemap().map((entry) => new URL(entry.url));
    expect(urls.map((url) => url.pathname)).toEqual(PUBLIC_MARKETING_ROUTES);
    expect(new Set(urls.map((url) => url.href)).size).toBe(PUBLIC_MARKETING_ROUTES.length);
    for (const url of urls) {
      expect(url.origin).toBe('https://www.logyourbody.com');
    }
  });

  it('omits modification dates until content revisions are available', () => {
    for (const entry of sitemap()) {
      expect(entry.lastModified).toBeUndefined();
    }
  });

  it('disallows legacy auth and private routes without excluding public pages', () => {
    const { rules } = robots();
    expect(rules).toEqual(
      expect.objectContaining({
        disallow: expect.arrayContaining(['/signin', '/signup', '/dashboard/', '/api/']),
      }),
    );
    const { disallow } = rules as { disallow: string[] };
    for (const route of PUBLIC_MARKETING_ROUTES) {
      expect(disallow.some((prefix) => route.startsWith(prefix))).toBe(false);
    }
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
