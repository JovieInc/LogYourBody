'use client';

import { StatsigClient } from '@statsig/js-client';

export interface StatsigAnalyticsConfig {
    clientKey: string;
    environmentTier?: string;
}

export type AnalyticsProperties = Record<string, string | number | boolean | null | undefined>;

let client: StatsigClient | null = null;
let initialized = false;
let initPromise: Promise<void> | null = null;

function getOrInitClient(config: StatsigAnalyticsConfig): StatsigClient | null {
    if (typeof window === 'undefined') {
        return null;
    }

    if (!config.clientKey) {
        return null;
    }

    if (!client) {
        client = new StatsigClient(
            config.clientKey,
            {},
            {
                environment: {
                    tier: config.environmentTier ?? 'development',
                },
            },
        );
    }

    if (!initialized && !initPromise) {
        initPromise = client
            .initializeAsync()
            .then(() => {
                initialized = true;
            })
            .catch(() => {
                // Swallow initialization errors for now; caller methods will no-op on failure.
            })
            .finally(() => {
                initPromise = null;
            });
    }

    return client;
}

export function createStatsigAnalytics(config: StatsigAnalyticsConfig) {
    const safeConfig: StatsigAnalyticsConfig = {
        clientKey: config.clientKey,
        environmentTier: config.environmentTier ?? 'development',
    };

    return {
        identify(userId: string | null, traits?: Record<string, string | number | boolean | null | undefined>): void {
            const c = getOrInitClient(safeConfig);
            if (!c) {
                return;
            }

            const user: { userID?: string; custom?: Record<string, string | number | boolean | null | undefined> } = {};

            if (userId && userId.trim().length > 0) {
                user.userID = userId;
            }

            if (traits && Object.keys(traits).length > 0) {
                user.custom = traits;
            }

            void c.updateUserAsync(user).catch(() => {
                // Ignore user update errors.
            });
        },

        track(event: string, properties?: AnalyticsProperties): void {
            const c = getOrInitClient(safeConfig);
            if (!c) {
                return;
            }

            if (!properties || Object.keys(properties).length === 0) {
                c.logEvent(String(event));
                return;
            }

            c.logEvent({
                eventName: String(event),
                metadata: properties,
            });
        },

        reset(): void {
            const c = getOrInitClient(safeConfig);
            if (!c) {
                return;
            }

            void c.updateUserAsync({ userID: undefined }).catch(() => {
                // Ignore reset errors.
            });
        },

        isFeatureEnabled(flagKey: string): boolean {
            const c = getOrInitClient(safeConfig);
            if (!c) {
                return false;
            }

            try {
                return c.checkGate(flagKey);
            } catch {
                return false;
            }
        },
    };
}
