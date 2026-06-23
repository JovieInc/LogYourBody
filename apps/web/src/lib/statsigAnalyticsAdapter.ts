'use client';

import { StatsigClient, type StatsigUser } from '@statsig/js-client';

export interface StatsigAnalyticsConfig {
    clientKey: string;
    environmentTier?: string;
}

export type AnalyticsProperties = Record<string, string | number | boolean | null | undefined>;

function sanitizeTraits(
    traits: Record<string, string | number | boolean | null | undefined>,
): StatsigUser['custom'] {
    const custom: NonNullable<StatsigUser['custom']> = {};

    for (const [key, value] of Object.entries(traits)) {
        if (value === null || value === undefined) {
            continue;
        }

        if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
            custom[key] = value;
        }
    }

    return Object.keys(custom).length > 0 ? custom : undefined;
}

function sanitizeMetadata(properties: AnalyticsProperties): Record<string, string> | undefined {
    const metadata: Record<string, string> = {};

    for (const [key, value] of Object.entries(properties)) {
        if (value === null || value === undefined) {
            continue;
        }

        metadata[key] = String(value);
    }

    return Object.keys(metadata).length > 0 ? metadata : undefined;
}

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

            const user: StatsigUser = {};

            if (userId && userId.trim().length > 0) {
                user.userID = userId;
            }

            if (traits && Object.keys(traits).length > 0) {
                user.custom = sanitizeTraits(traits);
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

            const metadata = properties ? sanitizeMetadata(properties) : undefined;

            if (!metadata) {
                c.logEvent(String(event));
                return;
            }

            c.logEvent({
                eventName: String(event),
                metadata,
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
