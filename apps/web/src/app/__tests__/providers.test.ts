import { needsProductAuthRuntime } from '../providers';

describe('needsProductAuthRuntime', () => {
  it.each([
    '/',
    '/about',
    '/blog/body-composition',
    '/brand',
    '/careers',
    '/changelog',
    '/delete-account',
    '/download/ios',
    '/health-disclosure',
    '/consumer-health-data',
    '/privacy',
    '/support',
    '/terms',
    '/security',
    '/mobile',
    '/landing',
    '/dashboard',
    '/onboarding',
    '/settings/profile',
    '/unknown',
    null,
    undefined,
  ])('keeps %s free of the product auth runtime', (pathname) => {
    expect(needsProductAuthRuntime(pathname)).toBe(false);
  });

  it.each(['/signin', '/signup'])('keeps product auth runtime enabled for %s', (pathname) => {
    expect(needsProductAuthRuntime(pathname)).toBe(true);
  });
});
