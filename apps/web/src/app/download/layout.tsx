import type { Metadata } from 'next';

export const metadata: Metadata = {
  description:
    'Download LogYourBody - The most advanced body composition tracking app. Available on iOS and Android.',
};

export default function DownloadLayout({ children }: { children: React.ReactNode }) {
  return children;
}
