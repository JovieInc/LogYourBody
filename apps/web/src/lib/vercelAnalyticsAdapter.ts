'use client';

import { track as trackVercelEvent } from '@vercel/analytics';

type AnalyticsProperties = Record<string, string | number | boolean | null | undefined>;

export interface VercelAnalyticsPort {
  track(event: string, properties?: AnalyticsProperties): void;
}

export function createVercelAnalytics(): VercelAnalyticsPort {
  return {
    track(event, properties) {
      const safeProperties = Object.fromEntries(
        Object.entries(properties ?? {}).filter(([, value]) => value !== undefined),
      ) as Record<string, string | number | boolean | null>;

      try {
        trackVercelEvent(event, safeProperties);
      } catch {
        // Analytics must never interrupt the conversion path.
      }
    },
  };
}
