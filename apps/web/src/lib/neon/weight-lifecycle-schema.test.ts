import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const migrationSql = readFileSync(
  join(process.cwd(), 'db/migrations/20261025120000_weight_lifecycle.sql'),
  'utf8',
);

describe('weight lifecycle schema', () => {
  it('keeps canonical kilograms, revisions, agent origin, and idempotent receipts', () => {
    expect(migrationSql).toContain('alter column weight type numeric(12, 6)');
    expect(migrationSql).toContain('add column if not exists revision integer not null default 1');
    expect(migrationSql).toContain("check (origin in ('web', 'native', 'agent'))");
    expect(migrationSql).toContain('primary key (user_subject, operation_id)');
    expect(migrationSql).toContain('public.weight_lifecycle_command');
    expect(migrationSql).toContain("'not_claimed'");
    expect(migrationSql).not.toContain('deleted_at = null');
    expect(migrationSql).toContain('stale_revision');
    expect(migrationSql).toContain('already_deleted');
    expect(migrationSql).toContain('idempotency_conflict');
  });
});
