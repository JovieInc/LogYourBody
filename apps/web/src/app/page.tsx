'use client';

import { LANDING_FLAGS } from '@/lib/flags/landing';
import { FullLandingPage } from './FullLandingPage';
import { MinimalWaitlistLanding } from './MinimalWaitlistLanding';

export default function HomePage() {
  if (LANDING_FLAGS.FULL_LANDING_ENABLED) {
    return <FullLandingPage />;
  }

  return <MinimalWaitlistLanding />;
}
