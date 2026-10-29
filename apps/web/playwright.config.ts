import { defineConfig, devices } from '@playwright/test';

// Next.js and Playwright must agree on the same port in local and CI runs.
const port = Number(process.env.PORT ?? 3000);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT must be an integer between 1 and 65535');
}
const baseURL = `http://127.0.0.1:${port}`;
const chromiumLaunchOptions = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
  ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH }
  : undefined;

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
    baseURL,

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
        launchOptions: chromiumLaunchOptions,
        viewport: { width: 360, height: 640 },
      },
    },

    // Mobile landscape (640×360)
    {
      name: 'mobile-landscape',
      use: {
        ...devices['Pixel 5 landscape'],
        launchOptions: chromiumLaunchOptions,
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
        launchOptions: chromiumLaunchOptions,
        viewport: { width: 1280, height: 800 },
      },
    },
  ],

  /* Run your local dev server before starting the tests */
  webServer: {
    command: process.env.CI
      ? `pnpm run build && pnpm run start --hostname 127.0.0.1 --port ${port}`
      : `pnpm run dev --hostname 127.0.0.1 --port ${port}`,
    url: baseURL,
    // These are prelaunch fixtures. Ambient rollout flags or a reused server
    // must not silently replace the waitlist with an App Store link.
    env: {
      NEXT_PUBLIC_LYB_APP_STORE_LIVE: '0',
      NEXT_PUBLIC_LYB_LANDING_ART_DIRECTION_V2: '0',
      NEXT_PUBLIC_LYB_WAITLIST_V2: '0',
    },
    reuseExistingServer: false,
    timeout: 120 * 1000,
  },
});
