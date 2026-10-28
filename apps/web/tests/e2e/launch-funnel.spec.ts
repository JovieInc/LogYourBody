import { expect, test } from '@playwright/test';
import { logYourBody } from '@jovieinc/product-registry';

// Run against the prelaunch configuration. Accepted/error responses below are
// intercepted: these cases verify browser behavior, not database commissioning.
test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
});

for (const path of ['/', '/download/ios', '/support', '/privacy', '/terms', '/delete-account']) {
  test(`launch surface ${path} renders without a page exception`, async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (error) => errors.push(error.message));
    const response = await page.goto(path);
    expect(response?.status()).toBe(200);
    await expect(page.getByRole('main')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    const canonicalPath = path === '/download/ios' ? '/' : path;
    const canonical = page.locator('link[rel="canonical"]');
    await expect(canonical).toHaveCount(1);
    // Next omits the root slash; URL normalization preserves equivalent origins.
    expect(new URL((await canonical.getAttribute('href'))!).href).toBe(
      new URL(canonicalPath, logYourBody.links.home).href,
    );
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    expect(errors).toEqual([]);
  });
}

test('waitlist validates, recovers after failure, and accepts once', async ({ page }) => {
  const requests: Record<string, unknown>[] = [];
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  let releaseResponse: (() => void) | undefined;
  await page.route('**/api/waitlist', async (route) => {
    requests.push(route.request().postDataJSON());
    if (requests.length === 1) {
      await route.fulfill({ status: 503, json: { success: false } });
      return;
    }
    await new Promise<void>((resolve) => {
      releaseResponse = resolve;
    });
    await route.fulfill({ status: 202, json: { success: true } });
  });
  await page.goto('/?utm_source=untrusted-campaign');
  const email = page.getByRole('textbox', { name: 'Email', exact: true });
  const submit = page.getByRole('button', { name: 'Request early access', exact: true });
  await submit.click();
  await expect(page.locator('#waitlist-status').getByRole('alert')).toHaveText(
    logYourBody.messages.waitlist.invalidEmail,
  );
  expect(requests).toHaveLength(0);
  await email.fill('launch-fixture@example.com');
  await submit.click();
  await expect(page.locator('#waitlist-status')).toHaveText(logYourBody.messages.waitlist.error);
  await expect(submit).toBeEnabled();
  await expect(email).toHaveValue('launch-fixture@example.com');
  await submit.click();
  await expect.poll(() => requests.length).toBe(2);
  await expect(submit).toBeDisabled();
  await expect(email).toBeDisabled();
  expect(requests[1]).toEqual({
    email: 'launch-fixture@example.com',
    source: 'landing:minimal:other',
    website: '',
  });
  await expect.poll(() => Boolean(releaseResponse)).toBe(true);
  releaseResponse!();
  await expect(page.locator('#waitlist-status')).toHaveText(logYourBody.messages.waitlist.success);
  await expect(submit).toBeDisabled();
  expect(requests).toHaveLength(2);
  expect(errors).toEqual([]);
});

test('network failure preserves the email and offers a retry', async ({ page }) => {
  await page.route('**/api/waitlist', (route) => route.abort('failed'));
  await page.goto('/');
  const email = page.getByRole('textbox', { name: 'Email', exact: true });
  const submit = page.getByRole('button', { name: 'Request early access', exact: true });
  await email.fill('launch-fixture@example.com');
  await submit.click();
  await expect(page.locator('#waitlist-status')).toHaveText(logYourBody.messages.waitlist.error);
  await expect(email).toHaveValue('launch-fixture@example.com');
  await expect(submit).toBeEnabled();
});

test('keyboard users can reach signup and the support escape path', async ({ page }) => {
  await page.goto('/');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: 'Skip to content' })).toBeFocused();
  await page.keyboard.press('Enter');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('textbox', { name: 'Email', exact: true })).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(
    page.getByRole('button', { name: 'Request early access', exact: true }),
  ).toBeFocused();
  const support = page.getByRole('link', { name: 'Support', exact: true });
  await support.focus();
  await page.keyboard.press('Enter');
  await expect(page).toHaveURL(/\/support$/);
  await expect(page.getByRole('heading', { name: 'How can we help?' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Delete account', exact: true })).toBeVisible();
});
