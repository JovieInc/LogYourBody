// LogYourBody web golden-path flow for the certify walker (JovieInc/ci certify/walk).
// Canary only: the walker passes an account whose email matches
// goldenPath.accounts.emailPattern in certification/app.json. The paid path is
// iOS (StoreKit); the web leg covers visit and install intent, and records where
// the web hands off to the iPhone app.
export default async function flow({ page, snap, settle, account, baseUrl }) {
  await page.goto(baseUrl, { waitUntil: 'networkidle' });
  await snap('visit', 'Homepage first screen');

  await page.getByText('Reference pricing', { exact: false }).scrollIntoViewIfNeeded();
  await snap('visit', 'Price on the homepage');

  await page.goto(`${baseUrl}/download/ios`, { waitUntil: 'networkidle' });
  await snap('install', 'Download for iPhone');

  const email = page.locator('input[type=email]').first();
  if (await email.count()) {
    await email.fill(account.email);
    await page.getByRole('button', { name: /request early access/i }).first().click();
    await settle();
    await snap('install', 'Early access requested with the canary address');
  }

  await page.goto(`${baseUrl}/signup`, { waitUntil: 'networkidle' });
  await snap('sign-in', 'Web account creation (hands off to Sign in with Apple)');
}
