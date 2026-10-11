'use client';

import { StatsigClient } from '@statsig/js-client';
import {
  isAnalyticsEvent,
  sanitizeAnalyticsPrincipal,
  sanitizeAnalyticsProperties,
  sanitizeAnalyticsTraits,
} from './analytics-schema';

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
    identify(userId: string | null, traits?: object): void {
      const c = getOrInitClient(safeConfig);
      if (!c) {
        return;
      }

      const user: { userID?: string; custom?: Record<string, string | number | boolean> } = {};

      user.userID = sanitizeAnalyticsPrincipal(userId);

      const safeTraits = sanitizeAnalyticsTraits(traits);
      if (safeTraits.platform) user.custom = { platform: safeTraits.platform };

      void c.updateUserAsync(user).catch(() => {
        // Ignore user update errors.
      });
    },

    track(event: string, properties?: object): void {
      if (!isAnalyticsEvent(event)) return;
      const c = getOrInitClient(safeConfig);
      if (!c) {
        return;
      }

      const metadata = sanitizeAnalyticsProperties(event, properties);
      if (Object.keys(metadata).length === 0) {
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
