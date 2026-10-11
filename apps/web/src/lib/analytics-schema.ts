// Closed app-level values: never derive analytics metadata from user content.
export const WAITLIST_CAMPAIGNS = [
  'direct',
  'instagram',
  'tiktok',
  'youtube',
  'newsletter',
  'referral',
  'search',
  'other',
] as const;

const landingProperties = {
  landing_id: ['minimal_waitlist_v1'],
  variant: ['waitlist_minimal', 'waitlist_editorial_v2'],
  campaign: WAITLIST_CAMPAIGNS,
  audience: ['men', 'women'],
  goal: ['recomposition', 'fat-loss', 'muscle-gain'],
  assignment_source: ['experiment', 'campaign', 'returning'],
} as const;

const eventProperties = {
  app_open: {},
  web_landing_viewed: landingProperties,
  web_waitlist_started: landingProperties,
  web_waitlist_submit_attempted: landingProperties,
  web_waitlist_submit_result: {
    outcome: ['invalid', 'accepted', 'rate_limited', 'server_error'],
  },
  // Legacy name means browser acceptance, including duplicates/honeypots.
  web_waitlist_submitted: landingProperties,
  web_cta_clicked: {},
  login_attempt: { method: ['apple'] },
  login_failed: {},
  logout: {},
} as const;

export type AnalyticsEvent = keyof typeof eventProperties;
export type AnalyticsProperties = Partial<{
  landing_id: 'minimal_waitlist_v1';
  variant: 'waitlist_minimal' | 'waitlist_editorial_v2';
  campaign: (typeof WAITLIST_CAMPAIGNS)[number];
  audience: 'men' | 'women';
  goal: 'recomposition' | 'fat-loss' | 'muscle-gain';
  assignment_source: 'experiment' | 'campaign' | 'returning';
  outcome: 'invalid' | 'accepted' | 'rate_limited' | 'server_error';
  method: 'apple';
}>;
export interface AnalyticsUserTraits {
  platform?: 'web' | 'ios';
}

export function isAnalyticsEvent(event: string): event is AnalyticsEvent {
  return Object.hasOwn(eventProperties, event);
}

export function sanitizeAnalyticsProperties(
  event: AnalyticsEvent,
  properties?: object,
): Record<string, string> {
  const allowed: Record<string, readonly string[]> = eventProperties[event];
  return Object.fromEntries(
    Object.entries(properties ?? {}).filter(
      ([key, value]) =>
        typeof value === 'string' && Object.hasOwn(allowed, key) && allowed[key].includes(value),
    ),
  );
}

export function sanitizeAnalyticsTraits(traits?: object): AnalyticsUserTraits {
  const platform = (traits as AnalyticsUserTraits | undefined)?.platform;
  return platform === 'web' || platform === 'ios' ? { platform } : {};
}

// The auth port supplies an opaque product principal, never an email/token.
export function sanitizeAnalyticsPrincipal(userId: string | null): string | undefined {
  return userId && /^[a-z0-9_-]{1,128}$/i.test(userId) ? userId : undefined;
}

export function waitlistCampaign(value: string | null): (typeof WAITLIST_CAMPAIGNS)[number] {
  if (!value) return 'direct';
  const normalized = value.toLowerCase();
  return WAITLIST_CAMPAIGNS.find((campaign) => campaign === normalized) ?? 'other';
}
