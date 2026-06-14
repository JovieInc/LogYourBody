import { needsClerkRuntime } from '../providers';

describe('needsClerkRuntime', () => {
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
  ])('keeps %s free of the Clerk runtime', (pathname) => {
    expect(needsClerkRuntime(pathname)).toBe(false);
  });

  it.each([
    '/signin',
    '/signup',
    '/dashboard',
    '/landing',
    '/onboarding',
    '/settings/profile',
    '/unknown',
  ])('keeps Clerk runtime enabled for %s', (pathname) => {
    expect(needsClerkRuntime(pathname)).toBe(true);
  });
});
