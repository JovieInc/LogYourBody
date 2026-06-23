import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const rootMigrationUrl = new URL(
  '../../../supabase/migrations/20260611003000_drop_permissive_rls_guard.sql',
  import.meta.url,
);

const dataExportsMigrationUrl = new URL(
  '../../../supabase/migrations/20260623003240_align_data_exports_user_id.sql',
  import.meta.url,
);

const rootMigrationSql = readFileSync(rootMigrationUrl, 'utf8');
const dataExportsMigrationSql = readFileSync(dataExportsMigrationUrl, 'utf8');

describe('RLS policy guard migration', () => {
  it('keeps the root migration tree canonical', () => {
    const legacyWebMigrationDir = new URL('../../../apps/web/supabase/migrations', import.meta.url);
    const rootMigrationDir = new URL('../../../supabase/migrations', import.meta.url);

    expect(existsSync(legacyWebMigrationDir)).toBe(false);
    expect(readdirSync(rootMigrationDir).some((fileName) => fileName.endsWith('.sql'))).toBe(true);
  });

  it('drops the permissive authenticated policies from active tables and storage', () => {
    ['profiles', 'body_metrics', 'daily_metrics', 'progress_photos', 'email_subscriptions'].forEach(
      (tableName) => {
        expect(rootMigrationSql).toContain(
          `DROP POLICY IF EXISTS "Authenticated users can manage ${tableName}" ON public.${tableName};`,
        );
      },
    );

    expect(rootMigrationSql).toContain(
      'DROP POLICY IF EXISTS "Authenticated users can manage photos" ON storage.objects;',
    );
    expect(rootMigrationSql).toContain(
      'DROP POLICY IF EXISTS "Public photo access" ON storage.objects;',
    );
    expect(rootMigrationSql).toContain(
      'DROP POLICY IF EXISTS "Anyone can view photos" ON storage.objects;',
    );
  });

  it('reasserts Clerk user-scoped policies for health and photo data', () => {
    [
      "id = auth.jwt()->>'sub'",
      "user_id = auth.jwt()->>'sub'",
      "(storage.foldername(name))[1] = auth.jwt()->>'sub'",
    ].forEach((predicate) => {
      expect(rootMigrationSql).toContain(predicate);
    });

    expect(rootMigrationSql).toContain(
      'CREATE POLICY "Users can delete own body metrics" ON public.body_metrics',
    );
    expect(rootMigrationSql).toContain(
      'CREATE POLICY "Users can delete own daily metrics" ON public.daily_metrics',
    );
    expect(rootMigrationSql).toContain(
      'CREATE POLICY "Users can delete own progress photos" ON public.progress_photos',
    );
    expect(rootMigrationSql).toContain(
      'CREATE POLICY "Users can delete own photos" ON storage.objects',
    );
  });

  it('locks down backup tables that may retain permissive policies after rename', () => {
    [
      'profiles_old',
      'body_metrics_old',
      'daily_metrics_old',
      'progress_photos_old',
      'weight_logs_old',
      'email_subscriptions_old',
    ].forEach((tableName) => {
      expect(rootMigrationSql).toContain(`'${tableName}'`);
    });

    expect(rootMigrationSql).toContain(
      "EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', table_name);",
    );
    expect(rootMigrationSql).toContain("'DROP POLICY IF EXISTS %I ON public.%I'");
  });

  it('fails closed if a blanket authenticated or public policy remains', () => {
    expect(rootMigrationSql).toContain('FROM pg_policies');
    expect(rootMigrationSql).toContain("'authenticated' = ANY(roles)");
    expect(rootMigrationSql).toContain("'public' = ANY(roles)");
    expect(rootMigrationSql).toContain("COALESCE(qual, '') IN ('true', '(true)')");
    expect(rootMigrationSql).toContain("COALESCE(with_check, '') IN ('true', '(true)')");
    expect(rootMigrationSql).toContain('RAISE EXCEPTION');
  });

  it('does not add new blanket authenticated policies', () => {
    expect(rootMigrationSql).not.toMatch(/TO authenticated\\s+USING \\(true\\)/);
    expect(rootMigrationSql).not.toMatch(/TO authenticated[\\s\\S]*WITH CHECK \\(true\\)/);
    expect(rootMigrationSql).not.toContain('FOR ALL TO authenticated');
  });

  it('keeps data export ownership aligned to Clerk text ids', () => {
    expect(dataExportsMigrationSql).toContain('ALTER COLUMN user_id TYPE TEXT USING user_id::text');
    expect(dataExportsMigrationSql).toContain('ALTER COLUMN user_id SET NOT NULL');
    expect(dataExportsMigrationSql).toContain('DROP CONSTRAINT %I');
    expect(dataExportsMigrationSql).toContain('TO service_role');
    expect(dataExportsMigrationSql).not.toContain('TO authenticated');
    expect(dataExportsMigrationSql).not.toContain('TO public');
  });

  it('keeps the photos bucket private and policy-scoped', () => {
    expect(rootMigrationSql).toContain("bucket_id = 'photos'");
    expect(rootMigrationSql).toContain("(storage.foldername(name))[1] = auth.jwt()->>'sub'");
    expect(rootMigrationSql).toContain(
      'DROP POLICY IF EXISTS "Public photo access" ON storage.objects;',
    );
    expect(rootMigrationSql).toContain(
      'DROP POLICY IF EXISTS "Anyone can view photos" ON storage.objects;',
    );
  });
});
