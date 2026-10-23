import type { Metadata } from 'next';
import { logYourBody } from '@jovieinc/product-registry';
import { LaunchLanding } from '../../LaunchLanding';

export const revalidate = false;

export const metadata: Metadata = {
  title: `${logYourBody.identity.name} for iPhone`,
  description: logYourBody.messages.landing.subheading,
};

// Share the canonical product proof and existing App Store/waitlist gate.
export default function IOSDownloadPage() {
  return <LaunchLanding landingId="ios_download_v1" />;
}
