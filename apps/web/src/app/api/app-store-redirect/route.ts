import { NextRequest, NextResponse } from 'next/server';
import { APP_STORE_URL } from '@/constants/app';

export async function GET(request: NextRequest) {
  // You can add analytics tracking here
  const platform = request.nextUrl.searchParams.get('platform') || 'ios';
  const source = request.nextUrl.searchParams.get('source') || 'website';

  // Log the conversion event (replace with your analytics)
  console.log('App Store redirect:', { platform, source, timestamp: new Date().toISOString() });

  // Redirect URLs (replace with actual URLs when available)
  const redirectUrls = {
    ios: APP_STORE_URL,
    android: 'https://play.google.com/store/apps/details?id=com.logyourbody.app',
  };

  const redirectUrl = redirectUrls[platform as keyof typeof redirectUrls] || redirectUrls.ios;

  return NextResponse.redirect(redirectUrl);
}
