import { expect, test } from '@playwright/test';
import { healthVaultWidgetDocument } from '../../src/lib/mcp/health-vault/widget';

test('health data loads only from LogYourBody origins', async ({ page }) => {
  const requests: string[] = [];
  const html = healthVaultWidgetDocument('https://www.logyourbody.com').replace(
    '<script>',
    `<script>
      window.openai = {
        toolResponseMetadata: { mcp_tool_result: { _meta: { viewHandle: 'vh_playwright_handle' } } },
        callTool: function () { return undefined; }
      };
    `,
  );
  await page.route('**/*', async (route) => {
    const url = route.request().url();
    requests.push(url);
    if (url.includes('/api/health-vault/view')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          confirmToken: 'ct_playwright_confirm',
          dexa: [
            { id: 'dx1', measuredOn: '2026-01-01', bodyFatPercent: 17.3417, leanMassKg: 60.5 },
          ],
          photos: [
            { id: 'ph_SENTINEL', imageUrl: 'https://photos.logyourbody.com/sentinel.png' },
            { id: 'evil', imageUrl: 'https://evil.example/secret.png' },
          ],
          weighIns: [{ id: 'w1', measuredOn: '2026-02-02', weightKg: 81.2229 }],
        }),
      });
      return;
    }
    if (url.startsWith('https://photos.logyourbody.com/')) {
      await route.fulfill({
        status: 200,
        contentType: 'image/png',
        body: Buffer.from([137, 80, 78, 71]),
      });
      return;
    }
    await route.abort();
  });

  await page.setContent(html, { waitUntil: 'load' });

  await expect(page.locator('#lyb-status')).toHaveText('Loaded from LogYourBody.');
  await expect(page.locator('img')).toHaveCount(1);
  await expect(page.locator('img')).toHaveAttribute(
    'src',
    'https://photos.logyourbody.com/sentinel.png',
  );
  const hosts = requests.map((url) => new URL(url).host);
  expect(hosts.length).toBeGreaterThan(0);
  expect(
    hosts.every((host) => host === 'www.logyourbody.com' || host === 'photos.logyourbody.com'),
  ).toBe(true);
  expect(requests.some((url) => url.includes('evil.example'))).toBe(false);
});
