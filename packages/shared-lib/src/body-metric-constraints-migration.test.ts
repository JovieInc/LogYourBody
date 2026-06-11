import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migrationSql = readFileSync(
  new URL(
    '../../../supabase/migrations/20260611002000_restore_body_metrics_constraints.sql',
    import.meta.url,
  ),
  'utf8',
);

describe('body metric constraints migration', () => {
  it('restores the body_metrics guardrail constraints', () => {
    expect(migrationSql).toContain('ADD CONSTRAINT weight_range_check');
    expect(migrationSql).toContain('ADD CONSTRAINT body_fat_percentage_range_check');
    expect(migrationSql).toContain('ADD CONSTRAINT muscle_mass_range_check');
  });

  it('preserves pre-existing invalid values before validation', () => {
    expect(migrationSql.indexOf('pre_constraint_invalid_values')).toBeLessThan(
      migrationSql.indexOf('VALIDATE CONSTRAINT weight_range_check'),
    );
    expect(migrationSql).toContain('source_metadata');
    expect(migrationSql).toContain('jsonb_strip_nulls');
  });

  it('rejects impossible future weight and body fat values', () => {
    expect(migrationSql).toContain("weight_unit = 'kg' AND weight BETWEEN 11.3 AND 453.6");
    expect(migrationSql).toContain("weight_unit = 'lbs' AND weight BETWEEN 25 AND 1000");
    expect(migrationSql).toContain('body_fat_percentage BETWEEN 0 AND 70');
  });
});
