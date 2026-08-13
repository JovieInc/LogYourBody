/**
 * Landing page feature flags.
 *
 * Production ships a minimal waitlist hero. ART_DIRECTION_V2_ENABLED is the
 * rollback gate for the production waitlist redesign. WAITLIST_V2_ENABLED
 * gates editorial waitlist audience routing in middleware.
 */
export const LANDING_FLAGS = {
  WAITLIST_V2_ENABLED: process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 === '1',
  ART_DIRECTION_V2_ENABLED: process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2 === '1',
} as const;
