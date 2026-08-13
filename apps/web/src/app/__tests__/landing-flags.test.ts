describe('landing flags', () => {
  const originalWaitlistV2Flag = process.env.NEXT_PUBLIC_LYB_WAITLIST_V2;
  const originalArtDirectionFlag = process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2;

  afterEach(() => {
    process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 = originalWaitlistV2Flag;
    process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2 = originalArtDirectionFlag;
    jest.resetModules();
  });

  it('defaults waitlist v2 to off and enables it only with an explicit flag', async () => {
    delete process.env.NEXT_PUBLIC_LYB_WAITLIST_V2;
    let flags = (await import('@/lib/flags/landing')).LANDING_FLAGS;
    expect(flags.WAITLIST_V2_ENABLED).toBe(false);

    jest.resetModules();
    process.env.NEXT_PUBLIC_LYB_WAITLIST_V2 = '1';
    flags = (await import('@/lib/flags/landing')).LANDING_FLAGS;
    expect(flags.WAITLIST_V2_ENABLED).toBe(true);
  });

  it('defaults the art direction to off and enables it only with an explicit flag', async () => {
    delete process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2;
    let flags = (await import('@/lib/flags/landing')).LANDING_FLAGS;
    expect(flags.ART_DIRECTION_V2_ENABLED).toBe(false);

    jest.resetModules();
    process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2 = '1';
    flags = (await import('@/lib/flags/landing')).LANDING_FLAGS;
    expect(flags.ART_DIRECTION_V2_ENABLED).toBe(true);
  });
});
