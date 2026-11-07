import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const record = JSON.parse(
  readFileSync(
    new URL('../decisions/photo-privacy-health-isolation.json', import.meta.url),
    'utf8',
  ),
);

describe('LYB-304 photo privacy and health-data isolation decision', () => {
  it('records the accepted default for LYB-173', () => {
    expect(record).toMatchObject({
      id: 'LYB-304',
      parent: 'LYB-173',
      status: 'accepted',
      approval_basis: 'ships-if-unanswered',
    });
  });

  it.each(['jovie_health_access', 'third_party_source_writes', 'synthetic_labeled_as_capture'])(
    'requires %s to be explicitly false',
    (flag) => {
      expect(record[flag], `${flag} must be present and false`).toBe(false);
    },
  );

  it('explains permissions at the moment of benefit and keeps provenance a tap away', () => {
    expect(record.permission_explanation.timing).toBe('moment_of_benefit');
    expect(record.permission_explanation.policy).toContain('moment of benefit');
    expect(record.provenance.access).toBe('tap_target');
    expect(record.provenance.policy).toContain('tap target');
  });

  it('records user-controlled retention and private-by-default sharing', () => {
    expect(record.photo_retention.until).toBe('photo_or_account_deleted');
    expect(record.photo_sharing).toMatchObject({
      default: 'private',
      requires_explicit_user_action: true,
    });
  });
});
