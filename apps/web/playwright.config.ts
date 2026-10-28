import { defineConfig, devices } from '@playwright/test';

/**
 * Read environment variables from file.
 * https://github.com/motdotla/dotenv
 */
// require('dotenv').config()

/**
 * See https://playwright.dev/docs/test-configuration.
 */
export default defineConfig({
  testDir: './tests/e2e',
  /* Run tests in files in parallel */
  fullyParallel: true,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: process.env.CI ? 'html' : 'list',
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: process.env.CI ? 'http://localhost:3000' : 'http://localhost:5173',

    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: 'on-first-retry',

    /* Screenshot options for visual regression testing */
    screenshot: {
      mode: 'only-on-failure',
      fullPage: true,
    },
  },

  /* Configure projects for major browsers and viewports */
  projects: [
    // Mobile portrait (360×640)
    {
      name: 'mobile-portrait',
      use: {
        ...devices['Pixel 5'],
        viewport: { width: 360, height: 640 },
      },
    },

    // Mobile landscape (640×360)
    {
      name: 'mobile-landscape',
      use: {
        ...devices['Pixel 5 landscape'],
        viewport: { width: 640, height: 360 },
      },
    },

    // Tablet (834×1112 - iPad Pro 11")
    {
      name: 'tablet',
      use: {
        ...devices['iPad Pro 11'],
        viewport: { width: 834, height: 1112 },
      },
    },

    // Desktop (1280×800)
    {
      name: 'desktop',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1280, height: 800 },
      },
    },
  ],

  /* Run your local dev server before starting the tests */
  webServer: {
    command: process.env.CI ? 'pnpm run build && pnpm run start' : 'pnpm run dev',
    url: process.env.CI ? 'http://localhost:3000' : 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },
});
