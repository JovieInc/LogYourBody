import {
  analyticsTierFromEnv,
  resolveAnalyticsTier,
  type AnalyticsTierInputs,
} from '../analytics-tier';

describe('analytics environment tier (LYB-226)', () => {
  it.each<[string, AnalyticsTierInputs, string]>([
    ['production deploy without any override', { vercelEnv: 'production' }, 'production'],
    [
      'production deploy with a stale development override',
      { vercelEnv: 'production', explicit: 'development' },
      'production',
    ],
    [
      'production deploy with an invalid override',
      { vercelEnv: 'production', explicit: 'prod' },
      'production',
    ],
    ['self-hosted production build', { nodeEnv: 'production' }, 'production'],
    [
      'production build with an invalid override',
      { nodeEnv: 'production', explicit: 'live' },
      'production',
    ],
    [
      'production build with an empty Vercel value',
      { nodeEnv: 'production', vercelEnv: '' },
      'production',
    ],
    ['preview deploy', { vercelEnv: 'preview', nodeEnv: 'production' }, 'staging'],
    [
      'preview deploy with an explicit staging tier',
      { vercelEnv: 'preview', explicit: 'staging' },
      'staging',
    ],
    ['local development', { nodeEnv: 'development' }, 'development'],
    ['test run', { nodeEnv: 'test' }, 'development'],
    ['nothing set', {}, 'development'],
  ])('%s', (_name, inputs, expected) => {
    expect(resolveAnalyticsTier(inputs)).toBe(expected);
  });

  it('never defaults a production deployment or build to development', () => {
    for (const explicit of [undefined, '', 'development', 'staging', 'bogus']) {
      expect(resolveAnalyticsTier({ explicit, vercelEnv: 'production' })).toBe('production');
      expect(
        resolveAnalyticsTier({
          explicit: explicit === 'development' ? undefined : explicit,
          nodeEnv: 'production',
          vercelEnv: undefined,
        }),
      ).not.toBe('development');
    }
  });

  describe('client bundle inputs', () => {
    const env = process.env as Record<string, string | undefined>;
    const original = {
      tier: env.NEXT_PUBLIC_STATSIG_ENV_TIER,
      vercel: env.NEXT_PUBLIC_VERCEL_ENV,
      node: env.NODE_ENV,
    };

    afterEach(() => {
      env.NEXT_PUBLIC_STATSIG_ENV_TIER = original.tier;
      env.NEXT_PUBLIC_VERCEL_ENV = original.vercel;
      env.NODE_ENV = original.node;
    });

    it('derives production from the exposed Vercel environment with no tier variable set', () => {
      delete env.NEXT_PUBLIC_STATSIG_ENV_TIER;
      env.NEXT_PUBLIC_VERCEL_ENV = 'production';
      env.NODE_ENV = 'production';

      expect(analyticsTierFromEnv()).toBe('production');
    });
  });

  it('exposes the Vercel environment to the client build', async () => {
    const { default: nextConfig } = await import('../../../next.config');

    expect(nextConfig.env).toHaveProperty('NEXT_PUBLIC_VERCEL_ENV');
  });
});
