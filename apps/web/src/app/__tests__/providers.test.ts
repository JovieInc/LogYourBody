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
    '/privacy',
    '/support',
    '/terms',
  ])('keeps %s free of the product auth runtime', (pathname) => {
    expect(needsProductAuthRuntime(pathname)).toBe(false);
  });

  it.each([
    '/signin',
    '/signup',
    '/dashboard',
    '/landing',
    '/onboarding',
    '/settings/profile',
    '/unknown',
  ])('keeps product auth runtime enabled for %s', (pathname) => {
    expect(needsProductAuthRuntime(pathname)).toBe(true);
  });
});
