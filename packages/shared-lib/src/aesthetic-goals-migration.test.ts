import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migrationSql = readFileSync(
  new URL(
    '../../../supabase/migrations/20260714230234_stop_implicit_aesthetic_goal_defaults.sql',
    import.meta.url,
  ),
  'utf8',
);

describe('individualized aesthetic goals migration', () => {
  it('removes automatic sex-based goal assignment for future profile writes', () => {
    expect(migrationSql).toContain(
      'drop trigger if exists set_default_goals_trigger on public.profiles;',
    );
    expect(migrationSql).toContain('drop function if exists public.set_default_goals();');
  });

  it('does not rewrite existing or explicitly selected goal values', () => {
    expect(migrationSql).not.toMatch(/\b(update|insert|delete|truncate)\b/i);
  });

  it('documents goal columns as optional user-selected targets', () => {
    [
      'goal_body_fat_percentage',
      'goal_ffmi',
      'goal_waist_to_hip_ratio',
      'goal_waist_to_height_ratio',
    ].forEach((columnName) => {
      expect(migrationSql).toContain(`comment on column public.profiles.${columnName}`);
    });

    expect(migrationSql.match(/explicitly selected by the user/g)).toHaveLength(4);
  });
});
