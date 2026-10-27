'use client';

import { StatsigClient } from '@statsig/js-client';
import {
  isAnalyticsEvent,
  sanitizeAnalyticsPrincipal,
  sanitizeAnalyticsProperties,
  sanitizeAnalyticsTraits,
} from './analytics-schema';
import { analyticsTierFromEnv } from './analytics-tier';

export interface StatsigAnalyticsConfig {
  clientKey: string;
  environmentTier?: string;
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
          tier: config.environmentTier ?? analyticsTierFromEnv(),
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

// SDK construction, browser storage and SDK methods can fail synchronously too.
// Keep optional measurement from interrupting signup or auth, and let the next
// call retry initialization. Never log the SDK error or user payload here.
function withClient<T>(config: StatsigAnalyticsConfig, action: (client: StatsigClient) => T) {
  try {
    const current = getOrInitClient(config);
    return current ? action(current) : undefined;
  } catch {
    return undefined;
  }
}

export function createStatsigAnalytics(config: StatsigAnalyticsConfig) {
  const safeConfig: StatsigAnalyticsConfig = {
    clientKey: config.clientKey,
    environmentTier: config.environmentTier ?? analyticsTierFromEnv(),
  };

  return {
    identify(userId: string | null, traits?: object): void {
      withClient(safeConfig, (c) => {
        const user: { userID?: string; custom?: Record<string, string | number | boolean> } = {};

        user.userID = sanitizeAnalyticsPrincipal(userId);

        const safeTraits = sanitizeAnalyticsTraits(traits);
        if (safeTraits.platform) user.custom = { platform: safeTraits.platform };

        void c.updateUserAsync(user).catch(() => {
          // Ignore user update errors.
        });
      });
    },

    track(event: string, properties?: object): void {
      if (!isAnalyticsEvent(event)) return;
      withClient(safeConfig, (c) => {
        const metadata = sanitizeAnalyticsProperties(event, properties);
        if (Object.keys(metadata).length === 0) {
          c.logEvent(String(event));
          return;
        }

        c.logEvent({
          eventName: String(event),
          metadata,
        });
      });
    },

    reset(): void {
      withClient(safeConfig, (c) => {
        void c.updateUserAsync({ userID: undefined }).catch(() => {
          // Ignore reset errors.
        });
      });
    },

    isFeatureEnabled(flagKey: string): boolean {
      return withClient(safeConfig, (c) => c.checkGate(flagKey)) ?? false;
    },
  };
}
