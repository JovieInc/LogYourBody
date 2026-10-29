import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const migrationSql = readFileSync(
  join(process.cwd(), 'db/migrations/20261025190000_gym_registry.sql'),
  'utf8',
);

describe('gym registry migration', () => {
  it('forces row level security so one subject cannot read another', () => {
    expect(migrationSql).toContain('create table if not exists public.gyms');
    expect(migrationSql).toContain('user_subject text not null');
    expect(migrationSql).toContain('alter table public.gyms enable row level security');
    expect(migrationSql).toContain('alter table public.gyms force row level security');
    expect(migrationSql).toContain(
      "user_subject = nullif(current_setting('app.current_user_subject', true), '')",
    );
    expect(migrationSql).toContain("values ('20261025190000_gym_registry')");
    expect(migrationSql).not.toMatch(/latitude|longitude|geog|geometry/i);
  });
});
