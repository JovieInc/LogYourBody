import 'server-only';
import { readPublicLandingGate } from '@/lib/adapters/StatsigPublicLandingAdapter.server';

export const EDITORIAL_HOMEPAGE_GATE = 'lyb_editorial_homepage_v1';

export function readEditorialHomepageRollout(): Promise<boolean> {
  return readPublicLandingGate(EDITORIAL_HOMEPAGE_GATE);
}
