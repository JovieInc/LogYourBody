import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const migrationSql = readFileSync(
  join(process.cwd(), 'db/migrations/20260813120000_native_body_metrics_sync.sql'),
  'utf8',
);

describe('native body metrics Neon schema', () => {
  it('adds native identity, local date, timestamps, and bone mass without truncating them', () => {
    expect(migrationSql).toContain('add column if not exists measured_at timestamptz');
    expect(migrationSql).toContain('add column if not exists local_date date');
    expect(migrationSql).toContain('add column if not exists bone_mass numeric(10, 2)');
    expect(migrationSql).toContain('add column if not exists client_created_at timestamptz');
    expect(migrationSql).toContain('add column if not exists client_updated_at timestamptz');
    expect(migrationSql).toContain('add column if not exists deleted_at timestamptz');
    expect(migrationSql).not.toContain('numeric(5, 2)');
  });

  it('stops collapsing same-day native records while keeping web daily upserts', () => {
    expect(migrationSql).toContain('drop constraint if exists body_metrics_user_date_unique');
    expect(migrationSql).toContain(
      'create unique index if not exists body_metrics_web_subject_date_unique',
    );
    expect(migrationSql).toContain("where origin = 'web' and deleted_at is null");
    expect(migrationSql.indexOf('body_metrics_web_subject_date_unique')).toBeLessThan(
      migrationSql.indexOf('drop constraint if exists body_metrics_user_date_unique'),
    );
  });

  it('scopes incremental pull to owner plus server updated_at', () => {
    expect(migrationSql).toContain(
      'create index if not exists body_metrics_owner_updated_idx',
    );
    expect(migrationSql).toContain('(user_subject, updated_at asc, id asc)');
  });
});
