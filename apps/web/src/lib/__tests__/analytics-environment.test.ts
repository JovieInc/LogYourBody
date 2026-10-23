jest.mock('@statsig/js-client', () => ({
  StatsigClient: jest.fn(() => ({
    initializeAsync: jest.fn().mockResolvedValue(undefined),
    logEvent: jest.fn(),
  })),
}));
jest.mock('@vercel/analytics', () => ({ track: jest.fn() }));

describe('web analytics deployment tier', () => {
  const originalEnvironment = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnvironment, NEXT_PUBLIC_STATSIG_CLIENT_KEY: 'synthetic-key' };
    delete process.env.NEXT_PUBLIC_STATSIG_ENV_TIER;
    delete process.env.VERCEL_ENV;
  });

  afterEach(() => {
    process.env = originalEnvironment;
  });

  it.each([
    ['production', 'production', undefined, 'production'],
    ['production', 'production', '', 'production'],
    ['production', 'production', ' \n', 'production'],
    ['development', 'production', undefined, 'production'],
    ['production', 'preview', undefined, 'staging'],
    ['production', undefined, undefined, 'production'],
    ['development', undefined, undefined, 'development'],
    ['production', 'preview', 'custom-tier', 'custom-tier'],
  ])(
    'bakes the tier into the public build config (%s, %s, %s)',
    async (node, vercel, tier, expected) => {
      Object.assign(process.env, { NODE_ENV: node });
      if (vercel) process.env.VERCEL_ENV = vercel;
      if (tier !== undefined) process.env.NEXT_PUBLIC_STATSIG_ENV_TIER = tier;
      const { default: config } = await import('../../../next.config');

      expect(config.env?.NEXT_PUBLIC_STATSIG_ENV_TIER).toBe(expected);
    },
  );

  it.each([undefined, '', ' \n', 'production', 'staging'])(
    'never defaults a production browser client to development with tier %p',
    async (tier) => {
      Object.assign(process.env, { NODE_ENV: 'production' });
      if (tier !== undefined) process.env.NEXT_PUBLIC_STATSIG_ENV_TIER = tier;
      // VERCEL_ENV is server-only; the browser must use the baked public value.
      const { analytics } = await import('../analytics');
      const { StatsigClient: Client } = await import('@statsig/js-client');
      analytics.track('web_landing_viewed');

      expect(Client).toHaveBeenCalledWith(
        'synthetic-key',
        {},
        {
          environment: { tier: tier?.trim() || 'production' },
        },
      );
    },
  );
});
