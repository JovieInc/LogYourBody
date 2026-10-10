'use client';

import { createStatsigAnalytics, type StatsigAnalyticsConfig } from './statsigAnalyticsAdapter';
import { createVercelAnalytics } from './vercelAnalyticsAdapter';
import {
  isAnalyticsEvent,
  sanitizeAnalyticsProperties,
  sanitizeAnalyticsTraits,
  type AnalyticsEvent,
  type AnalyticsProperties,
  type AnalyticsUserTraits,
} from './analytics-schema';

export type { AnalyticsEvent, AnalyticsProperties, AnalyticsUserTraits } from './analytics-schema';

export interface AnalyticsPort {
  identify(userId: string | null, traits?: AnalyticsUserTraits): void;
  track(event: AnalyticsEvent, properties?: AnalyticsProperties): void;
  reset(): void;
  isFeatureEnabled(flagKey: string): boolean;
}

const config: StatsigAnalyticsConfig = {
  clientKey: process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY ?? '',
  environmentTier: process.env.NEXT_PUBLIC_STATSIG_ENV_TIER ?? 'development',
};

const statsig = createStatsigAnalytics(config);
const vercel = createVercelAnalytics();

export const analytics: AnalyticsPort = {
  identify(userId, traits) {
    statsig.identify(userId, sanitizeAnalyticsTraits(traits));
  },
  track(event, properties) {
    if (!isAnalyticsEvent(event)) return;
    const safeProperties = sanitizeAnalyticsProperties(event, properties);
    statsig.track(event, safeProperties);
    vercel.track(event, safeProperties);
  },
  reset: statsig.reset,
  isFeatureEnabled: statsig.isFeatureEnabled,
};
