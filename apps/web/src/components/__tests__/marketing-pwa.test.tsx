import { act, render, screen } from '@testing-library/react';
import { PWAInstallPrompt } from '../PWAInstallPrompt';
import { ServiceWorkerUpdater } from '../ServiceWorkerUpdater';
import { isMarketingPath } from '@/data/marketingNavigation';
// Next's optimized icon imports use a default export for each deep module.
// The shared test mapper points those modules at one fixture; provide both shapes.
jest.mock('lucide-react', () => {
  const Icon = () => <svg aria-hidden="true" />;
  return { __esModule: true, default: Icon, X: Icon, Share: Icon, Plus: Icon, Smartphone: Icon };
});
let mockPathname = '/';
jest.mock('next/navigation', () => ({ usePathname: () => mockPathname }));

describe('marketing stays on the native acquisition path', () => {
  const originalUserAgent = Object.getOwnPropertyDescriptor(navigator, 'userAgent');
  const originalMatchMedia = window.matchMedia;
  beforeEach(() => {
    jest.useFakeTimers();
    localStorage.removeItem('pwa-install-dismissed');
    Object.defineProperty(navigator, 'userAgent', {
      configurable: true,
      value:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
    });
    window.matchMedia = jest.fn().mockImplementation((query) => ({
      matches: query === '(display-mode: browser)',
      media: query,
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
    }));
  });
  afterEach(() => {
    if (originalUserAgent) Object.defineProperty(navigator, 'userAgent', originalUserAgent);
    else delete (navigator as unknown as Record<string, unknown>).userAgent;
    window.matchMedia = originalMatchMedia;
    jest.useRealTimers();
  });
  it.each([
    '/',
    '/about',
    '/blog/retired-article',
    '/brand',
    '/careers',
    '/changelog',
    '/delete-account',
    '/download/ios',
    '/download/android',
    '/health-disclosure',
    '/landing',
    '/mobile',
    '/privacy',
    '/security',
    '/support',
    '/terms',
  ])('does not offer an install/update prompt or schedule one on %s', (pathname) => {
    mockPathname = pathname;
    const { container, unmount } = render(
      <>
        <PWAInstallPrompt />
        <ServiceWorkerUpdater />
      </>,
    );
    act(() => {
      jest.advanceTimersByTime(60000);
    });
    expect(container).toBeEmptyDOMElement();
    expect(jest.getTimerCount()).toBe(0);
    unmount();
  });
  it('proves the same iPhone browser stimulus offers installation on a protected route', () => {
    mockPathname = '/dashboard';
    const { unmount } = render(<PWAInstallPrompt />);
    expect(jest.getTimerCount()).toBe(1);
    act(() => {
      jest.advanceTimersByTime(30000);
    });
    expect(screen.getByRole('heading', { name: 'Install LogYourBody' })).toBeVisible();
    unmount();
  });
  it('preserves the protected product route classification', () => {
    for (const pathname of ['/dashboard', '/settings/profile', '/signup', '/signin'])
      expect(isMarketingPath(pathname)).toBe(false);
  });
});
