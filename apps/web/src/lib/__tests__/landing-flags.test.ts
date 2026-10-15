describe('landing art-direction rollback switch', () => {
  const original = process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2;

  afterEach(() => {
    if (original === undefined) delete process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2;
    else process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2 = original;
    jest.resetModules();
  });

  it.each([
    ['1', true],
    ['1\n', true],
    [' 1 \n', true],
    ['0\n', false],
    ['true', false],
    ['', false],
    [undefined, false],
  ])('reads the deployed value %p as %p', async (value, enabled) => {
    jest.resetModules();
    if (value === undefined) delete process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2;
    else process.env.NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2 = value as string;
    const { LANDING_FLAGS } = await import('../flags/landing');
    expect(LANDING_FLAGS.ART_DIRECTION_V2_ENABLED).toBe(enabled);
  });
});
