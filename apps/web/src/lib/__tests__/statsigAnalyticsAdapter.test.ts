import { StatsigClient } from '@statsig/js-client';
import { createStatsigAnalytics } from '../statsigAnalyticsAdapter';

jest.mock('@statsig/js-client', () => ({
  StatsigClient: jest.fn(() => ({
    initializeAsync: jest.fn().mockResolvedValue(undefined),
    updateUserAsync: jest.fn().mockResolvedValue(undefined),
    logEvent: jest.fn(),
    checkGate: jest.fn().mockReturnValue(false),
  })),
}));

it('enforces the schema at the Statsig adapter and never forwards contact or health traits', () => {
  const port = createStatsigAnalytics({ clientKey: 'synthetic-key' });
  port.track('email=synthetic@example.com', { weight: 80 });
  expect(StatsigClient).not.toHaveBeenCalled();
  port.track('web_waitlist_submitted', {
    campaign: 'newsletter',
    email: 'synthetic@example.com',
    weight: 80,
  });
  const client = jest.mocked(StatsigClient).mock.results[0].value;
  expect(client.logEvent).toHaveBeenCalledWith({
    eventName: 'web_waitlist_submitted',
    metadata: { campaign: 'newsletter' },
  });
  port.identify('opaque-synthetic-principal', {
    email: 'synthetic@example.com',
    platform: 'web',
    body_fat: 20,
  });
  expect(client.updateUserAsync).toHaveBeenCalledWith({
    userID: 'opaque-synthetic-principal',
    custom: { platform: 'web' },
  });
});
