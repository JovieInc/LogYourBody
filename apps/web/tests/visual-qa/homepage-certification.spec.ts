import { expect, test } from '@playwright/test';

// Run with NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2=1 to certify the gated
// public design, and without it to exercise the rollback form.
test('homepage conversion preserves geometry across response states', async ({ page }) => {
  test.setTimeout(120_000);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  let finishResponse: (() => void) | undefined;
  let status = 202;
  await page.route('**/api/waitlist', async (route) => {
    await new Promise<void>((resolve) => {
      finishResponse = resolve;
    });
    await route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify({ success: status === 202 }),
    });
  });

  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: width < 768 ? 844 : 900 });
    for (const outcome of [202, 400, 429, 500]) {
      status = outcome;
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      const email = page.getByRole('textbox', { name: 'Email', exact: true });
      const button = page.getByRole('button', { name: 'Request early access', exact: true });
      await expect(email).toBeVisible();
      await expect(button).toBeInViewport();
      await expect(page.locator('main button[type="submit"]')).toHaveCount(1);
      const geometry = async () =>
        Promise.all([
          email.boundingBox(),
          page.locator('main button[type="submit"]').boundingBox(),
          page.locator('#waitlist-status').boundingBox(),
        ]);
      const before = await geometry();
      expect(before[1]!.height).toBeGreaterThanOrEqual(44);
      await expect(button).toHaveCSS('font-weight', '510');
      expect(
        await button.locator('span').evaluate((node) => node.getBoundingClientRect().height),
      ).toBe(32);
      await email.fill('');
      await button.click();
      await expect(
        page.getByRole('alert').filter({ hasText: 'Enter a valid email' }),
      ).toBeVisible();
      expect(await geometry()).toEqual(before);
      await email.fill('certification@example.com');
      const request = page.waitForRequest('**/api/waitlist');
      await button.click();
      await request;
      await expect(page.getByRole('button', { name: 'Joining…' })).toBeDisabled();
      expect(await geometry()).toEqual(before);
      await expect.poll(() => Boolean(finishResponse)).toBe(true);
      finishResponse!();
      finishResponse = undefined;
      await expect(page.locator('#waitlist-status')).not.toBeEmpty();
      await expect(page.getByRole('button', { name: 'Joining…' })).toHaveCount(0);
      expect(await geometry()).toEqual(before);
      await expect(page.locator('#waitlist-status p')).toHaveCSS(
        'color',
        outcome === 202 ? 'rgb(17, 175, 255)' : 'rgb(255, 103, 125)',
      );
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
    }
  }
  expect(errors).toEqual([]);
});

test('homepage supports keyboard focus and reduced-motion hover', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: 'Skip to content' })).toBeFocused();
  await page.keyboard.press('Enter');
  const email = page.getByRole('textbox', { name: 'Email', exact: true });
  await page.keyboard.press('Tab');
  await expect(email).toBeFocused();
  await page.keyboard.press('Tab');
  const button = page.getByRole('button', { name: 'Request early access', exact: true });
  await expect(button).toBeFocused();
  await button.hover();
  await expect(button.locator('span')).toHaveCSS('transform', 'none');
  const signal = page.getByText('The daily measure', { exact: true }).locator('..');
  if (await signal.count()) {
    await signal.hover();
    await expect(signal.locator('span').nth(1)).toHaveCSS('transform', 'none');
  }
});
