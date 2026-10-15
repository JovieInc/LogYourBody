/** @jest-environment node */

const mockInitialize = jest.fn();
const mockGetGate = jest.fn();
const mockShutdown = jest.fn();

jest.mock('server-only', () => ({}));
jest.mock('@statsig/statsig-node-core', () => ({
  Statsig: jest.fn(() => ({
    initialize: mockInitialize,
    getFeatureGate: mockGetGate,
    shutdown: mockShutdown,
  })),
  StatsigUser: { withUserID: jest.fn((userID: string) => ({ userID })) },
}));

describe('public homepage rollout adapter', () => {
  const originalKey = process.env.STATSIG_SERVER_API_KEY;
  const originalTier = process.env.NEXT_PUBLIC_STATSIG_ENV_TIER;
  const originalVercelEnv = process.env.VERCEL_ENV;

  beforeEach(() => {
    jest.resetModules();
    jest.clearAllMocks();
    process.env.STATSIG_SERVER_API_KEY = 'synthetic-server-key';
    delete process.env.NEXT_PUBLIC_STATSIG_ENV_TIER;
    process.env.VERCEL_ENV = 'production';
    mockInitialize.mockResolvedValue({ isSuccess: true });
    mockShutdown.mockResolvedValue({ isSuccess: true });
    mockGetGate.mockReturnValue({
      value: true,
      getEvaluationDetails: () => ({ reason: 'Network' }),
    });
  });

  afterEach(() => {
    for (const [key, value] of Object.entries({
      STATSIG_SERVER_API_KEY: originalKey,
      NEXT_PUBLIC_STATSIG_ENV_TIER: originalTier,
      VERCEL_ENV: originalVercelEnv,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    jest.useRealTimers();
  });

  async function adapter() {
    return import('../flags/publicLanding.server');
  }

  it('stays off without a server key and never creates a provider client', async () => {
    delete process.env.STATSIG_SERVER_API_KEY;
    const { readEditorialHomepageRollout } = await adapter();
    expect(await readEditorialHomepageRollout()).toBe(false);
    expect(jest.requireMock('@statsig/statsig-node-core').Statsig).not.toHaveBeenCalled();
  });

  it('uses the configured environment, bounded initialization and one non-personal public identity', async () => {
    const { readEditorialHomepageRollout, EDITORIAL_HOMEPAGE_GATE } = await adapter();
    expect(await readEditorialHomepageRollout()).toBe(true);
    expect(await readEditorialHomepageRollout()).toBe(true);
    const sdk = jest.requireMock('@statsig/statsig-node-core');
    expect(sdk.Statsig).toHaveBeenCalledWith('synthetic-server-key', {
      environment: 'production',
      initTimeoutMs: 500,
      disableCountryLookup: true,
      outputLogLevel: 'none',
    });
    expect(mockInitialize).toHaveBeenCalledTimes(1);
    expect(mockGetGate).toHaveBeenCalledWith(
      { userID: 'lyb-public-homepage' },
      EDITORIAL_HOMEPAGE_GATE,
    );
    expect(mockGetGate).toHaveBeenCalledTimes(2);
  });

  it('respects an explicit Statsig tier and defaults local runs to development', async () => {
    process.env.NEXT_PUBLIC_STATSIG_ENV_TIER = 'staging';
    let reader = (await adapter()).readEditorialHomepageRollout;
    await reader();
    expect(
      jest.requireMock('@statsig/statsig-node-core').Statsig.mock.calls[0][1].environment,
    ).toBe('staging');
    jest.resetModules();
    delete process.env.NEXT_PUBLIC_STATSIG_ENV_TIER;
    delete process.env.VERCEL_ENV;
    reader = (await adapter()).readEditorialHomepageRollout;
    await reader();
    expect(
      jest.requireMock('@statsig/statsig-node-core').Statsig.mock.calls[0][1].environment,
    ).toBe('development');

    jest.resetModules();
    process.env.VERCEL_ENV = 'preview';
    reader = (await adapter()).readEditorialHomepageRollout;
    await reader();
    expect(
      jest.requireMock('@statsig/statsig-node-core').Statsig.mock.calls[0][1].environment,
    ).toBe('development');
  });

  it('coalesces concurrent cold starts', async () => {
    let complete!: (value: { isSuccess: boolean }) => void;
    mockInitialize.mockReturnValue(
      new Promise((resolve) => {
        complete = resolve;
      }),
    );
    const { readEditorialHomepageRollout } = await adapter();
    const decisions = [readEditorialHomepageRollout(), readEditorialHomepageRollout()];
    expect(mockInitialize).toHaveBeenCalledTimes(1);
    complete({ isSuccess: true });
    expect(await Promise.all(decisions)).toEqual([true, true]);
  });

  it('keeps missing, closed and failed gate evaluations off', async () => {
    const { readEditorialHomepageRollout } = await adapter();
    mockGetGate.mockReturnValueOnce({
      value: true,
      getEvaluationDetails: () => ({ reason: 'Unrecognized' }),
    });
    expect(await readEditorialHomepageRollout()).toBe(false);
    mockGetGate.mockReturnValueOnce({
      value: false,
      getEvaluationDetails: () => ({ reason: 'Network' }),
    });
    expect(await readEditorialHomepageRollout()).toBe(false);
    mockGetGate.mockImplementationOnce(() => {
      throw new Error('evaluation unavailable');
    });
    expect(await readEditorialHomepageRollout()).toBe(false);
  });

  it('cleans up failed initialization and permits a later retry', async () => {
    mockInitialize.mockResolvedValueOnce({ isSuccess: false });
    const { readEditorialHomepageRollout } = await adapter();
    expect(await readEditorialHomepageRollout()).toBe(false);
    await Promise.resolve();
    expect(mockShutdown).toHaveBeenCalledWith(250);
    expect(await readEditorialHomepageRollout()).toBe(true);
    expect(mockInitialize).toHaveBeenCalledTimes(2);
  });

  it('fails closed on rejected initialization and tolerates cleanup failure', async () => {
    mockInitialize.mockRejectedValueOnce(new Error('provider unavailable'));
    mockShutdown.mockRejectedValueOnce(new Error('shutdown unavailable'));
    const { readEditorialHomepageRollout } = await adapter();
    expect(await readEditorialHomepageRollout()).toBe(false);
    await Promise.resolve();
    expect(mockShutdown).toHaveBeenCalledWith(250);
  });

  it('fails closed when the SDK cannot be constructed', async () => {
    const { readEditorialHomepageRollout } = await adapter();
    jest.requireMock('@statsig/statsig-node-core').Statsig.mockImplementationOnce(() => {
      throw new Error('native SDK unavailable');
    });
    expect(await readEditorialHomepageRollout()).toBe(false);
    expect(mockInitialize).not.toHaveBeenCalled();
  });

  it('bounds a stalled initialization to 750ms', async () => {
    jest.useFakeTimers();
    mockInitialize.mockReturnValue(new Promise(() => {}));
    const { readEditorialHomepageRollout } = await adapter();
    const decision = readEditorialHomepageRollout();
    await jest.advanceTimersByTimeAsync(750);
    expect(await decision).toBe(false);
    expect(mockShutdown).toHaveBeenCalledWith(250);
  });
});
