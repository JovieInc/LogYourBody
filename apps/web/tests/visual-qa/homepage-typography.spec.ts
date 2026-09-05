import { expect, test } from '@playwright/test';

test('renders shared Jovie display and interface faces, including variable control weight', async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const session = await page.context().newCDPSession(page);
  await session.send('DOM.enable');
  await session.send('CSS.enable');

  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: width === 390 ? 844 : 900 });
    await page.goto('/');
    await page.locator('.lyb-landing h1').waitFor();
    await page.evaluate(() => document.fonts.ready);
    const { root } = await session.send('DOM.getDocument');
    for (const [selector, family] of [
      ['.lyb-landing h1', 'Satoshi'],
      ['.lyb-landing #early-access button span', 'Inter'],
      ['.lyb-landing section[aria-labelledby="landing-heading"] p', 'Inter'],
    ]) {
      const { nodeId } = await session.send('DOM.querySelector', { nodeId: root.nodeId, selector });
      const { fonts } = await session.send('CSS.getPlatformFontsForNode', { nodeId });
      const rendered = fonts.filter((font) => font.glyphCount > 0);
      expect(rendered.length).toBeGreaterThan(0);
      expect(rendered.every((font) => font.isCustomFont && font.familyName.includes(family))).toBe(
        true,
      );
    }
    const button = page.getByRole('button', { name: 'Request early access', exact: true });
    await expect(button).toHaveCSS('font-weight', '510');
    await expect(button).toBeInViewport();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
  }
});
