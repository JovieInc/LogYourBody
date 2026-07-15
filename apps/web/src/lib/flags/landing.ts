/**
 * Landing page feature flags.
 *
 * FULL_LANDING_ENABLED defaults to false so production ships the minimal
 * waitlist hero until the iOS app is live and marketing claims are verified.
 * Set NEXT_PUBLIC_LYB_FULL_LANDING=1 locally or in preview to render the
 * full System B marketing page.
 * ART_DIRECTION_V2_ENABLED is a separate rollback gate for the production
 * waitlist redesign. It must be explicitly enabled per deployment environment.
 */
export const LANDING_FLAGS = {
  FULL_LANDING_ENABLED: process.env.NEXT_PUBLIC_LYB_FULL_LANDING === '1',
  WAITLIST_V2_ENABLED: process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 === '1',
  ART_DIRECTION_V2_ENABLED: process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2 === '1',
} as const;
