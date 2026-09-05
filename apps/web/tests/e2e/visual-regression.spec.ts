import { test, expect } from '@playwright/test';

// List of all public routes to test
const publicRoutes = [
  { path: '/', name: 'home' },
  { path: '/login', name: 'login' },
  { path: '/signup', name: 'signup' },
  { path: '/about', name: 'about' },
  { path: '/privacy', name: 'privacy' },
  { path: '/terms', name: 'terms' },
  { path: '/blog', name: 'blog' },
  { path: '/careers', name: 'careers' },
  { path: '/changelog', name: 'changelog' },
  { path: '/security', name: 'security' },
];

// Visual regression test configuration
const visualRegressionConfig = {
  maxDiffPixels: 100, // Max number of different pixels allowed
  maxDiffPixelRatio: 0.001, // 0.1% pixel change tolerance
  threshold: 0.2, // Threshold between 0-1 for pixel comparison
  animations: 'disabled' as const,
};

test.describe('Visual Regression Tests', () => {
  // Run tests for each route
  for (const route of publicRoutes) {
    test(`${route.name} page visual regression`, async ({ page, browserName }, testInfo) => {
      // Navigate to the route
      await page.goto(route.path);

      // Wait for the page to be fully loaded
      await page.waitForLoadState('networkidle');

      // Wait for any animations to complete
      await page.waitForTimeout(500);

      // Disable animations and transitions for consistent screenshots
      await page.addStyleTag({
        content: `
          *, *::before, *::after {
            animation-duration: 0s !important;
            animation-delay: 0s !important;
            transition-duration: 0s !important;
            transition-delay: 0s !important;
          }
        `,
      });

      // Get the project name (viewport configuration)
      const projectName = testInfo.project.name;

      // Take a screenshot
      const screenshot = await page.screenshot({
        fullPage: true,
        animations: visualRegressionConfig.animations,
      });

      // Compare with baseline
      expect(screenshot).toMatchSnapshot(`${route.name}-${projectName}.png`, {
        maxDiffPixels: visualRegressionConfig.maxDiffPixels,
        maxDiffPixelRatio: visualRegressionConfig.maxDiffPixelRatio,
        threshold: visualRegressionConfig.threshold,
      });
    });
  }

  // Test specific UI states
  test('login form interaction states', async ({ page }, testInfo) => {
    await page.goto('/login');
    await page.waitForLoadState('networkidle');

    // Disable animations
    await page.addStyleTag({
      content: `
        *, *::before, *::after {
          animation-duration: 0s !important;
          transition-duration: 0s !important;
        }
      `,
    });

    const projectName = testInfo.project.name;

    // Test form focus state
    await page.focus('input[type="email"]');
    const focusScreenshot = await page.screenshot({
      fullPage: true,
      animations: visualRegressionConfig.animations,
    });

    expect(focusScreenshot).toMatchSnapshot(`login-form-focus-${projectName}.png`, {
      maxDiffPixels: visualRegressionConfig.maxDiffPixels,
      maxDiffPixelRatio: visualRegressionConfig.maxDiffPixelRatio,
      threshold: visualRegressionConfig.threshold,
    });

    // Test form with error state (submit empty form)
    await page.click('button[type="submit"]');
    await page.waitForTimeout(100); // Wait for error messages

    const errorScreenshot = await page.screenshot({
      fullPage: true,
      animations: visualRegressionConfig.animations,
    });

    expect(errorScreenshot).toMatchSnapshot(`login-form-error-${projectName}.png`, {
      maxDiffPixels: visualRegressionConfig.maxDiffPixels,
      maxDiffPixelRatio: visualRegressionConfig.maxDiffPixelRatio,
      threshold: visualRegressionConfig.threshold,
    });
  });

  // Test responsive navigation
  test('navigation menu states', async ({ page }, testInfo) => {
    const projectName = testInfo.project.name;

    // Skip desktop as it doesn't have a mobile menu
    if (projectName === 'desktop') {
      return;
    }

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Disable animations
    await page.addStyleTag({
      content: `
        *, *::before, *::after {
          animation-duration: 0s !important;
          transition-duration: 0s !important;
        }
      `,
    });

    // Look for mobile menu button and click if exists
    const menuButton = page.locator('button[aria-label*="menu" i]').first();
    if (await menuButton.isVisible()) {
      await menuButton.click();
      await page.waitForTimeout(100); // Wait for menu to open

      const menuOpenScreenshot = await page.screenshot({
        fullPage: true,
        animations: visualRegressionConfig.animations,
      });

      expect(menuOpenScreenshot).toMatchSnapshot(`navigation-menu-open-${projectName}.png`, {
        maxDiffPixels: visualRegressionConfig.maxDiffPixels,
        maxDiffPixelRatio: visualRegressionConfig.maxDiffPixelRatio,
        threshold: visualRegressionConfig.threshold,
      });
    }
  });
});

// Test to ensure all routes are accessible
test.describe('Route Accessibility', () => {
  for (const route of publicRoutes) {
    test(`${route.name} page loads successfully`, async ({ page }) => {
      const response = await page.goto(route.path);

      // Ensure the page loads successfully
      expect(response?.status()).toBeLessThan(400);

      // Ensure there are no console errors
      const errors: string[] = [];
      page.on('console', (msg) => {
        if (msg.type() === 'error') {
          errors.push(msg.text());
        }
      });

      await page.waitForLoadState('networkidle');

      // Allow some specific errors that are expected in development
      const filteredErrors = errors.filter((error) => {
        return (
          !error.includes('Failed to load resource') &&
          !error.includes('404') &&
          !error.includes('retired provider')
        );
      });

      expect(filteredErrors).toHaveLength(0);
    });
  }
});
