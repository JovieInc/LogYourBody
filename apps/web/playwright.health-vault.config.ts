import { defineConfig } from '@playwright/test';

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;

/** Widget network audit. Does not boot Next; the spec renders the widget HTML directly. */
export default defineConfig({
  testDir: './tests/e2e',
  testMatch: '**/health-vault-network.spec.ts',
  fullyParallel: false,
  retries: 0,
  reporter: 'list',
  use: {
    launchOptions: executablePath ? { executablePath } : undefined,
  },
});
