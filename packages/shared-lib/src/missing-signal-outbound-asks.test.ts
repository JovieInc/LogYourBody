import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Package-local decisions are Turbo inputs, so record changes invalidate the
// existing shared-lib CI test cache without workflow configuration changes.
const record = JSON.parse(
  readFileSync(new URL('../decisions/missing-signal-outbound-asks.json', import.meta.url), 'utf8'),
);

describe('LYB-306 missing-signal outbound asks decision', () => {
  it('explicitly disables outbound asks for this release', () => {
    // Strict equality also fails if the boolean is missing or is the string "false".
    expect(record.outbound_asks_enabled).toBe(false);
  });

  it('records a numeric cadence of zero for disabled outbound asks', () => {
    expect(record.max_outbound_cadence_days).toBeTypeOf('number');
    expect(record.max_outbound_cadence_days).toBe(0);
  });
});
