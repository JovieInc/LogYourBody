/** @jest-environment node */
import { existsSync } from 'node:fs';
import { join } from 'node:path';

// LYB-100 replaces the retired UI behavior with a permanent removal contract.
it.each([
  'app/settings/layout.tsx',
  'app/settings/page.tsx',
  'app/settings/account/page.tsx',
  'app/settings/data-export/page.tsx',
  'app/settings/notifications/page.tsx',
  'app/settings/preferences/page.tsx',
  'app/settings/subscription/page.tsx',
])('keeps retired web app UI %s unmounted', (file) => {
  expect(existsSync(join(process.cwd(), 'src', file))).toBe(false);
});
