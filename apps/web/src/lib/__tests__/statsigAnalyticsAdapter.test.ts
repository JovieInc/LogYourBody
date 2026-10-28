import type { StatsigClient as StatsigClientType } from '@statsig/js-client';
import type { createStatsigAnalytics as createStatsigAnalyticsType } from '../statsigAnalyticsAdapter';

jest.mock('@statsig/js-client', () => ({
  StatsigClient: jest.fn(() => ({
    initializeAsync: jest.fn().mockResolvedValue(undefined),
    updateUserAsync: jest.fn().mockResolvedValue(undefined),
    logEvent: jest.fn(),
    checkGate: jest.fn().mockReturnValue(false),
  })),
}));
jest.mock('@vercel/analytics', () => ({ track: jest.fn() }));

let StatsigClient: jest.MockedClass<typeof StatsigClientType>;
let createStatsigAnalytics: typeof createStatsigAnalyticsType;

beforeEach(async () => {
  jest.resetModules();
  StatsigClient = jest.mocked((await import('@statsig/js-client')).StatsigClient);
  createStatsigAnalytics = (await import('../statsigAnalyticsAdapter')).createStatsigAnalytics;
});

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

it('keeps conversion usable and permits retry when SDK construction throws', () => {
  StatsigClient.mockImplementationOnce(() => {
    throw new Error('SDK unavailable');
  });
  const port = createStatsigAnalytics({ clientKey: 'synthetic-key' });
  expect(() => port.track('web_waitlist_submit_attempted')).not.toThrow();
  port.track('web_waitlist_submitted');
  const client = StatsigClient.mock.results[1].value;
  expect(client.logEvent).toHaveBeenCalledWith('web_waitlist_submitted');
});

it('contains synchronous event, identity and gate failures', () => {
  const port = createStatsigAnalytics({ clientKey: 'synthetic-key' });
  port.track('web_landing_viewed');
  const client = StatsigClient.mock.results[0].value;
  client.logEvent.mockImplementation(() => {
    throw new Error('SDK storage unavailable');
  });
  client.updateUserAsync.mockImplementation(() => {
    throw new Error('SDK user update unavailable');
  });
  client.checkGate.mockImplementation(() => {
    throw new Error('SDK gate unavailable');
  });
  expect(() => port.track('web_waitlist_submitted', { campaign: 'search' })).not.toThrow();
  expect(() => port.track('web_waitlist_submit_result', { outcome: 'accepted' })).not.toThrow();
  expect(() => port.identify('opaque-principal', { platform: 'web' })).not.toThrow();
  expect(() => port.reset()).not.toThrow();
  expect(port.isFeatureEnabled('existing_gate')).toBe(false);
});

it('retries a synchronously failed initialization on the next call', () => {
  const client = {
    initializeAsync: jest
      .fn()
      .mockImplementationOnce(() => {
        throw new Error('SDK initialization unavailable');
      })
      .mockResolvedValue(undefined),
    logEvent: jest.fn(),
  };
  StatsigClient.mockImplementationOnce(() => client as unknown as StatsigClientType);
  const port = createStatsigAnalytics({ clientKey: 'synthetic-key' });
  expect(() => port.track('web_landing_viewed')).not.toThrow();
  expect(() => port.track('web_waitlist_started')).not.toThrow();
  expect(client.initializeAsync).toHaveBeenCalledTimes(2);
  expect(client.logEvent).toHaveBeenCalledWith('web_waitlist_started');
});

it('continues sending sanitized funnel evidence to the other adapter after SDK failure', async () => {
  const previousKey = process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY;
  process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY = 'synthetic-key';
  try {
    StatsigClient.mockImplementationOnce(() => {
      throw new Error('SDK unavailable');
    });
    const { analytics } = await import('../analytics');
    const { track } = await import('@vercel/analytics');
    analytics.track('web_waitlist_submit_result', {
      outcome: 'accepted',
      variant: 'waitlist_minimal',
    });
    expect(track).toHaveBeenCalledWith('web_waitlist_submit_result', {
      outcome: 'accepted',
      variant: 'waitlist_minimal',
    });
  } finally {
    if (previousKey === undefined) delete process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY;
    else process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY = previousKey;
  }
});
