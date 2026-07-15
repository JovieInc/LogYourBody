import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import { SpeedInsights } from '@vercel/speed-insights/next';
import { Providers } from './providers';
import { PWAInstallPrompt } from '@/components/PWAInstallPrompt';
import { ServiceWorkerUpdater } from '@/components/ServiceWorkerUpdater';
import './globals.css';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
});

export const metadata: Metadata = {
  title: {
    default: 'LogYourBody — Know if the work is working',
    template: '%s | LogYourBody',
  },
  description:
    'Weight, body fat, lean mass, and progress photos in one private iPhone timeline that shows the trend.',
  keywords: [
    'body composition',
    'fitness tracking',
    'weight tracking',
    'body fat',
    'health app',
    'lean body mass',
    'Apple Health',
  ],
  authors: [{ name: 'Tim White' }],
  creator: 'Tim White',
  publisher: 'LogYourBody',
  applicationName: 'LogYourBody',
  category: 'Health & Fitness',
  classification: 'Health',
  generator: 'Next.js',
  referrer: 'origin-when-cross-origin',
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  metadataBase: new URL('https://logyourbody.com'),
  alternates: {
    canonical: '/',
  },
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: 'https://logyourbody.com',
    siteName: 'LogYourBody',
    title: 'LogYourBody — Know if the work is working',
    description:
      'Weight, body fat, lean mass, and progress photos in one private iPhone timeline that shows the trend.',
    images: [
      {
        url: '/marketing/landing/hero-men-v1.png',
        width: 1536,
        height: 1024,
        alt: 'Athlete in a private performance studio after training',
        type: 'image/png',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    site: '@logyourbody',
    creator: '@itstimwhite',
    title: 'LogYourBody — Know if the work is working',
    description:
      'Weight, body fat, lean mass, and progress photos in one private iPhone timeline that shows the trend.',
    images: ['/marketing/landing/hero-men-v1.png'],
  },
  robots: {
    index: true,
    follow: true,
    nocache: false,
    googleBot: {
      index: true,
      follow: true,
      noimageindex: false,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  icons: {
    icon: [
      { url: '/favicon-16x16.png', sizes: '16x16', type: 'image/png' },
      { url: '/favicon-32x32.png', sizes: '32x32', type: 'image/png' },
    ],
    shortcut: '/favicon.ico',
    apple: [{ url: '/apple-touch-icon.png', sizes: '180x180', type: 'image/png' }],
    other: [
      {
        rel: 'android-chrome',
        url: '/android-chrome-192x192.png',
        sizes: '192x192',
        type: 'image/png',
      },
      {
        rel: 'android-chrome',
        url: '/android-chrome-512x512.png',
        sizes: '512x512',
        type: 'image/png',
      },
    ],
  },
  manifest: '/site.webmanifest',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'black-translucent',
    title: 'LogYourBody',
    startupImage: [
      {
        url: '/apple-touch-icon.png',
        media:
          '(device-width: 320px) and (device-height: 568px) and (-webkit-device-pixel-ratio: 2)',
      },
    ],
  },
};

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={inter.className}>
        <Providers>
          {children}
          <PWAInstallPrompt />
          <ServiceWorkerUpdater />
        </Providers>
        <SpeedInsights />
      </body>
    </html>
  );
}
