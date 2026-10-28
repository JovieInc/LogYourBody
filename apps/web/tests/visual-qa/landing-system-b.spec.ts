import { expect, test } from '@playwright/test';

const routes = [
  '/',
  '/download/ios',
  '/download/android',
  '/about',
  '/careers',
  '/brand',
  '/support',
  '/security',
  '/privacy',
  '/terms',
  '/health-disclosure',
  '/blog',
  '/changelog',
  '/delete-account',
];

test('all marketing routes reflow with one main, one heading, real controls and no runtime errors', async ({
  page,
}, info) => {
  test.setTimeout(90000);
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  for (const route of routes) {
    const response = await page.goto(route);
    expect(response?.status()).toBe(200);
    await page.evaluate(() => document.fonts.ready);
    await expect(page.getByRole('main')).toHaveCount(1);
    await expect(page.getByRole('heading', { level: 1 })).toHaveCount(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    expect(await page.locator('a button, button a').count()).toBe(0);
    for (const img of await page.locator('img').all()) {
      await img.scrollIntoViewIfNeeded();
      await expect
        .poll(
          () =>
            img.evaluate(
              (image) =>
                (image as HTMLImageElement).complete &&
                (image as HTMLImageElement).naturalWidth > 0,
            ),
          { message: `Images load on ${route}` },
        )
        .toBe(true);
    }
    await page.evaluate(() => scrollTo(0, 0));
    if (['/', '/about', '/brand'].includes(route))
      await info.attach(`${route || 'home'}-${info.project.name}`, {
        body: await page.screenshot({ fullPage: true }),
        contentType: 'image/png',
      });
  }
  expect(errors).toEqual([]);
});

test('canonical landing and primary sections match reviewed visual baselines', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => document.fonts.ready);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Know if the work is working.' }),
  ).toBeVisible();
  await expect(page).toHaveScreenshot('lyb-system-b-full-page.png', {
    fullPage: true,
    maxDiffPixelRatio: 0.01,
  });
  for (const [selector, filename] of [
    ['section[aria-labelledby="landing-heading"]', 'lyb-system-b-hero.png'],
    ['section[aria-labelledby="features-heading"]', 'lyb-launch-features.png'],
    ['section[aria-labelledby="pricing-heading"]', 'lyb-launch-pricing.png'],
    ['#early-access', 'lyb-launch-waitlist.png'],
  ])
    await expect(page.locator(selector)).toHaveScreenshot(filename, { maxDiffPixelRatio: 0.01 });
});

test('waitlist has stable hover, keyboard and async states without writing real records', async ({
  page,
}) => {
  await page.goto('/');
  await page.evaluate(() => document.fonts.ready);
  const input = page.getByRole('textbox', { name: 'Email' });
  const button = page.getByRole('button', { name: 'Request early access' });
  expect(
    await input.evaluate((node) => parseFloat(getComputedStyle(node).fontSize)),
  ).toBeGreaterThanOrEqual(16);
  const initial = await button.boundingBox();
  await button.hover();
  expect(await button.boundingBox()).toEqual(initial);
  await input.focus();
  await input.fill('qa@example.invalid');
  await page.keyboard.press('Tab');
  await expect(button).toBeFocused();
  const anchor = await page.locator('#features-heading').boundingBox();
  await page.route('**/api/waitlist', (route) =>
    route.fulfill({ status: 429, contentType: 'application/json', body: '{"success":false}' }),
  );
  await page.keyboard.press('Enter');
  await expect(page.getByText('Something went wrong. Please try again.')).toBeVisible();
  await expect(input).toHaveValue('qa@example.invalid');
  await expect(button).toBeEnabled();
  expect(await page.locator('#features-heading').boundingBox()).toEqual(anchor);
  await page.unroute('**/api/waitlist');
  await page.route('**/api/waitlist', (route) =>
    route.fulfill({ status: 202, contentType: 'application/json', body: '{"success":true}' }),
  );
  await button.click();
  await expect(page.getByText('Your early-access request was received.')).toBeVisible();
  await expect(button).toBeDisabled();
  expect(await page.locator('#features-heading').boundingBox()).toEqual(anchor);
});

test('retired articles recover without auth and old aliases reach the single funnel', async ({
  page,
}) => {
  for (const route of ['/landing', '/mobile', '/download']) {
    await page.goto(route);
    await expect(
      page.getByRole('heading', { level: 1, name: 'Know if the work is working.' }),
    ).toBeVisible();
  }
  const response = await page.goto('/blog/what-is-ffmi-and-why-it-matters');
  expect(response?.status()).toBe(404);
  await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Contact support' })).toHaveAttribute(
    'href',
    '/support',
  );
});

test('hero works at boundary widths, text growth, RTL and reduced motion', async ({ page }) => {
  for (const width of [320, 768, 1024, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('/');
    await expect(page.getByRole('button', { name: 'Request early access' })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
  }
  await page.setViewportSize({ width: 720, height: 900 });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  await page.addStyleTag({ content: 'html { font-size: 200%; }' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(
    await page.evaluate(
      () => document.getAnimations().filter((a) => a.playState === 'running').length,
    ),
  ).toBe(0);
  await page.evaluate(() => (document.documentElement.dir = 'rtl'));
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test('shared secondary-page semantics and mobile navigation remain accessible', async ({
  page,
}) => {
  await page.goto('/support');
  await expect(
    page.getByRole('link', { name: 'Request a data export by email', exact: true }),
  ).toHaveCSS('color', 'rgb(245, 247, 251)');
  expect(await page.locator('main').evaluate((node) => getComputedStyle(node).fontFamily)).toMatch(
    /Inter/i,
  );
  expect(await page.locator('h1').evaluate((node) => getComputedStyle(node).fontFamily)).toMatch(
    /Satoshi/i,
  );
  expect(
    await page
      .locator('.mf-eyebrow')
      .first()
      .evaluate((node) => getComputedStyle(node).fontFamily),
  ).toMatch(/Inter/i);
  await page.setViewportSize({ width: 393, height: 852 });
  const menu = page.locator('button[aria-controls="marketing-navigation"]');
  await menu.click();
  await expect(menu).toHaveAttribute('aria-expanded', 'true');
  const mobile = page.getByRole('navigation', { name: 'Mobile', exact: true });
  await expect(mobile.getByRole('link', { name: 'Request early access' })).toHaveAttribute(
    'href',
    '/download/ios',
  );
  await mobile.getByRole('link', { name: 'About' }).focus();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('navigation', { name: 'Mobile', exact: true })).toHaveCount(0);
  await expect(menu).toBeFocused();
});
