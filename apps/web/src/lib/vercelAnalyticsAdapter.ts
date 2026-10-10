'use client';

import { track as trackVercelEvent } from '@vercel/analytics';
import { isAnalyticsEvent, sanitizeAnalyticsProperties } from './analytics-schema';

export interface VercelAnalyticsPort {
  track(event: string, properties?: object): void;
}

export function createVercelAnalytics(): VercelAnalyticsPort {
  return {
    track(event, properties) {
      if (!isAnalyticsEvent(event)) return;
      const safeProperties = sanitizeAnalyticsProperties(event, properties);

      try {
        trackVercelEvent(event, safeProperties);
      } catch {
        // Analytics must never interrupt the conversion path.
      }
    },
  };
}
