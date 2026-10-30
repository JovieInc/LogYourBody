/** @jest-environment node */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const migrationSql = readFileSync(
  join(process.cwd(), 'db/migrations/20261030120000_health_vault_grants.sql'),
  'utf8',
);

describe('health vault grant schema', () => {
  it('stores opaque grants and consent field names, not measurements', () => {
    expect(migrationSql).toContain('create table if not exists public.health_vault_grants');
    expect(migrationSql).toContain('create table if not exists public.health_vault_consent_log');
    expect(migrationSql).toContain("check (kind in ('view', 'confirm', 'consent', 'media'))");
    expect(migrationSql).toContain("check (jsonb_typeof(fields) = 'array')");
    expect(migrationSql).toContain('insert into public.schema_migrations (version)');
    expect(migrationSql).toContain('20261030120000_health_vault_grants');
    expect(migrationSql).not.toContain('body_fat_percentage');
    expect(migrationSql).not.toContain('weight_kg');
    expect(migrationSql).not.toContain('photo_bytes');
  });
});
