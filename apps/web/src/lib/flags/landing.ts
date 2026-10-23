/**
 * Landing page feature flags.
 *
 * ART_DIRECTION_V2_ENABLED is the build-time rollback switch. The homepage also
 * requires the default-off Statsig gate lyb_editorial_homepage_v1, evaluated on
 * the server and refreshed through ISR. The legacy WAITLIST_V2_ENABLED switch
 * no longer assigns homepage audiences (LYB-226). APP_STORE_LIVE
 * switches the launch landing's primary action from the waitlist to the App
 * Store once the listing resolves.
 */
export const LANDING_FLAGS = {
  WAITLIST_V2_ENABLED: process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 === '1',
  ART_DIRECTION_V2_ENABLED: process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2?.trim() === '1',
  APP_STORE_LIVE: process.env.NEXT_PUBLIC_LYB_APP_STORE_LIVE === '1',
} as const;
