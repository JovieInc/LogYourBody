import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const migrationSql = readFileSync(
  join(process.cwd(), 'db/migrations/20260813130000_native_product_records.sql'),
  'utf8',
);

describe('native product records Neon schema', () => {
  it('stores remaining native collections as subject-scoped jsonb without backfill', () => {
    expect(migrationSql).toContain('create table if not exists public.native_records');
    expect(migrationSql).toContain('user_subject text not null');
    expect(migrationSql).toContain('payload jsonb not null');
    expect(migrationSql).toContain('primary key (collection, id)');
    expect(migrationSql).toContain("'daily_metrics'");
    expect(migrationSql).toContain("'glp1_medications'");
    expect(migrationSql).toContain("'glp1_dose_logs'");
    expect(migrationSql).toContain("'dexa_results'");
    expect(migrationSql).toContain("'progress_photos'");
    expect(migrationSql).toContain('No backfill');
  });

  it('indexes incremental pull by owner, collection, and updated_at', () => {
    expect(migrationSql).toContain('create index if not exists native_records_owner_updated_idx');
    expect(migrationSql).toContain('(user_subject, collection, updated_at asc, id asc)');
  });
});
