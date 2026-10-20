import { expect, test } from '@playwright/test';

async function freezePage(page: import('@playwright/test').Page) {
  await page.addStyleTag({
    content: `
      *, *::before, *::after {
        animation-duration: 0s !important;
        animation-delay: 0s !important;
        transition-duration: 0s !important;
        transition-delay: 0s !important;
        scroll-behavior: auto !important;
      }
      html {
        font-synthesis: none;
      }
    `,
  });
}

test.describe('LogYourBody System B landing visual QA', () => {
  test('captures the full landing page and primary sections', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    await freezePage(page);

    await expect(page.getByRole('heading', { level: 1, name: 'LogYourBody' })).toBeVisible();
    await expect(page.getByText('The mirror gets a memory.')).toBeVisible();
    await expect(page.getByText('Your body over time.')).toBeVisible();
    await expect(page.getByText('Start with one clean body log.')).toBeVisible();

    await expect(page).toHaveScreenshot('lyb-system-b-full-page.png', {
      fullPage: true,
      maxDiffPixelRatio: 0.01,
    });

    await expect(page.getByTestId('landing-hero')).toHaveScreenshot('lyb-system-b-hero.png', {
      maxDiffPixelRatio: 0.01,
    });

    await expect(page.getByTestId('progress-photos')).toHaveScreenshot(
      'lyb-system-b-progress-photos.png',
      {
        maxDiffPixelRatio: 0.01,
      },
    );

    await expect(page.getByTestId('timeline-section')).toHaveScreenshot(
      'lyb-system-b-timeline.png',
      {
        maxDiffPixelRatio: 0.01,
      },
    );
  });
});
