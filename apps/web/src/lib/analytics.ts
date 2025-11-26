'use client';

import { createStatsigAnalytics, type StatsigAnalyticsConfig } from './statsigAnalyticsAdapter';

export type AnalyticsEvent =
    | 'app_open'
    | 'web_landing_viewed'
    | 'web_cta_clicked'
    | 'login_attempt'
    | 'login_failed'
    | 'logout';

export type AnalyticsProperties = Record<string, string | number | boolean | null | undefined>;

export interface AnalyticsUserTraits {
    email?: string;
    name?: string;
    plan?: string;
    [key: string]: string | number | boolean | null | undefined;
}

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

const implementation = createStatsigAnalytics(config);

export const analytics: AnalyticsPort = implementation;
