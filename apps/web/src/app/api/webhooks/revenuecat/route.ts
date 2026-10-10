import { neonRevenueEvents } from '@/lib/neon/revenue-events-adapter';
import { createRevenueCatHandler } from './route-handlers';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const POST = createRevenueCatHandler({
  store: neonRevenueEvents,
  configuration: () => ({
    signingSecret: process.env.REVENUECAT_WEBHOOK_SIGNING_SECRET ?? '',
    allowedAppIds: (process.env.REVENUECAT_WEBHOOK_APP_IDS ?? '')
      .split(',')
      .map((id) => id.trim())
      .filter(Boolean),
  }),
  now: () => new Date(),
});
