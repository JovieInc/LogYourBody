describe('landing flags', () => {
  const originalFlag = process.env.NEXT_PUBLIC_LYB_FULL_LANDING;

  afterEach(() => {
    process.env.NEXT_PUBLIC_LYB_FULL_LANDING = originalFlag;
    jest.resetModules();
  });

  it('defaults full landing to off when env flag is unset', async () => {
    delete process.env.NEXT_PUBLIC_LYB_FULL_LANDING;
    const { LANDING_FLAGS } = await import('@/lib/flags/landing');
    expect(LANDING_FLAGS.FULL_LANDING_ENABLED).toBe(false);
  });

  it('enables full landing only when NEXT_PUBLIC_LYB_FULL_LANDING=1', async () => {
    process.env.NEXT_PUBLIC_LYB_FULL_LANDING = '1';
    const { LANDING_FLAGS } = await import('@/lib/flags/landing');
    expect(LANDING_FLAGS.FULL_LANDING_ENABLED).toBe(true);
  });
});
