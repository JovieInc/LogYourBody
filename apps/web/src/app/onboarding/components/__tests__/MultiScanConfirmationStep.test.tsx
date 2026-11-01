/** @jest-environment node */
import { existsSync } from 'node:fs';
import { join } from 'node:path';

// The native app owns this behavior; retain regression coverage for its web retirement.
describe('landing-only web (LYB-100)', () => {
  it.each(['onboarding/components/MultiScanConfirmationStep.tsx'])(
    'does not ship the retired %s UI',
    (file) => {
      expect(existsSync(join(process.cwd(), 'src/app', file))).toBe(false);
    },
  );
});
