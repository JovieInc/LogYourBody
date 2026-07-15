import { render } from '@testing-library/react';
import HomePage from '../page';
import robots from '../robots';
import sitemap from '../sitemap';

jest.mock('../MinimalWaitlistLanding', () => ({
  MinimalWaitlistLanding: () => <main data-testid="minimal-landing" />,
}));

jest.mock('../LegacyMinimalWaitlistLanding', () => ({
  LegacyMinimalWaitlistLanding: () => <main data-testid="legacy-minimal-landing" />,
}));

describe('marketing discovery routes', () => {
  it('publishes a nonempty robots policy and sitemap URL', () => {
    const value = robots();
    expect(value.sitemap).toBe('https://logyourbody.com/sitemap.xml');
    expect(value.rules).toEqual(expect.objectContaining({ userAgent: '*', allow: '/' }));
  });

  it('lists only intentional public launch surfaces', () => {
    const urls = sitemap().map((entry) => entry.url);
    expect(urls).toEqual([
      'https://logyourbody.com',
      'https://logyourbody.com/privacy',
      'https://logyourbody.com/terms',
      'https://logyourbody.com/health-disclosure',
      'https://logyourbody.com/support',
    ]);
    expect(urls.some((url) => url.includes('/dashboard'))).toBe(false);
  });

  it('always emits verified structured data on the default landing', () => {
    const { container } = render(<HomePage />);
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
