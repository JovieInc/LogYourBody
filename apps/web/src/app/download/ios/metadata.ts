import type { Metadata } from 'next';
import { endpoints } from '@/lib/generated/endpoints.generated';

export const metadata: Metadata = {
  title: 'Download LogYourBody for iOS - Body Composition Tracker',
  description:
    'Download LogYourBody on iPhone. Track FFMI, body fat percentage, and progress photos in one private timeline.',
  keywords: [
    'LogYourBody iOS',
    'body composition app iPhone',
    'FFMI calculator iOS',
    'fitness tracker iPhone',
    'body fat percentage app',
    'progress photos app',
    'Apple Health integration',
  ],
  openGraph: {
    title: 'LogYourBody for iOS - Your Body. Decoded.',
    description:
      'The only app that tracks FFMI, body fat percentage, and progress photos with scientific accuracy. Download free on App Store.',
    url: `${endpoints.hosts.marketing.url}/download/ios`,
    siteName: 'LogYourBody',
    images: [
      {
        url: '/og-image-ios.png',
        width: 1200,
        height: 630,
        alt: 'LogYourBody iOS App - Body Composition Tracking',
      },
    ],
    locale: 'en_US',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'LogYourBody for iOS - Your Body. Decoded.',
    description: 'Track body composition with scientific accuracy. Download free on App Store.',
    images: ['/og-image-ios.png'],
    creator: '@itstimwhite',
  },
  alternates: {
    canonical: '/download/ios',
  },
  robots: {
    index: true,
    follow: true,
  },
};
