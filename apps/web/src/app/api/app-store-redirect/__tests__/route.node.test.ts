/**
 * @jest-environment node
 */
import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';
import { APP_CONFIG, APP_STORE_URL } from '@/constants/app';
import { GET } from '../route';

jest.mock('next/server', () => ({
  NextResponse: {
    redirect: jest.fn((url: string) => ({
      headers: new Headers({ location: url }),
      status: 307,
    })),
  },
}));

function createRequest(url: string) {
  return {
    nextUrl: new URL(url),
  } as unknown as NextRequest;
}

describe('GET /api/app-store-redirect', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers().setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('redirects to the iOS App Store by default', async () => {
    const response = await GET(createRequest('https://logyourbody.com/api/app-store-redirect'));

    expect(NextResponse.redirect).toHaveBeenCalledWith(APP_STORE_URL);
    expect(response.headers.get('location')).toBe(APP_STORE_URL);
    expect(console.log).toHaveBeenCalledWith('App Store redirect:', {
      platform: 'ios',
      source: 'website',
      timestamp: '2026-01-02T03:04:05.000Z',
    });
  });

  it('redirects Android traffic to the Play Store URL', async () => {
    const response = await GET(
      createRequest('https://logyourbody.com/api/app-store-redirect?platform=android&source=qr'),
    );

    expect(NextResponse.redirect).toHaveBeenCalledWith(APP_CONFIG.playStoreUrl);
    expect(response.headers.get('location')).toBe(APP_CONFIG.playStoreUrl);
    expect(console.log).toHaveBeenCalledWith('App Store redirect:', {
      platform: 'android',
      source: 'qr',
      timestamp: '2026-01-02T03:04:05.000Z',
    });
  });

  it('falls back to the iOS URL for unknown platform values', async () => {
    const response = await GET(
      createRequest(
        'https://logyourbody.com/api/app-store-redirect?platform=desktop&source=footer',
      ),
    );

    expect(NextResponse.redirect).toHaveBeenCalledWith(APP_STORE_URL);
    expect(response.headers.get('location')).toBe(APP_STORE_URL);
    expect(console.log).toHaveBeenCalledWith('App Store redirect:', {
      platform: 'desktop',
      source: 'footer',
      timestamp: '2026-01-02T03:04:05.000Z',
    });
  });
});
