/** @jest-environment node */
import { existsSync } from 'node:fs';
import { join } from 'node:path';

// LYB-100 replaces the retired UI behavior with a permanent removal contract.
it.each(['app/log/page.tsx', 'app/log/DesktopLogStepContent.tsx'])(
  'keeps retired web app UI %s unmounted',
  (file) => {
    expect(existsSync(join(process.cwd(), 'src', file))).toBe(false);
  },
);
