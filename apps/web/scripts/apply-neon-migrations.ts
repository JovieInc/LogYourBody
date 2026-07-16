import 'server-only';

import { neon } from '@neondatabase/serverless';
import * as dotenv from 'dotenv';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';

dotenv.config({ path: path.resolve(process.cwd(), '.env.local') });

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('Missing DATABASE_URL');

const sql = neon(connectionString);
const migrationDirectory = path.resolve(process.cwd(), 'db/migrations');

async function main() {
  await sql`
    create table if not exists public.schema_migrations (
      version text primary key,
      applied_at timestamptz not null default now()
    )
  `;

  const files = (await fs.readdir(migrationDirectory))
    .filter((file) => file.endsWith('.sql'))
    .sort();
  const applied = (await sql`select version from public.schema_migrations`) as Array<{ version: string }>;
  const appliedVersions = new Set(applied.map(({ version }) => version));

  for (const file of files) {
    const version = file.replace(/\.sql$/, '');
    if (appliedVersions.has(version)) continue;

    const contents = await fs.readFile(path.join(migrationDirectory, file), 'utf8');
    console.log(`Applying ${file}`);
    await sql.query('begin');
    try {
      await sql.query(contents);
      await sql`
        insert into public.schema_migrations (version)
        values (${version})
        on conflict (version) do nothing
      `;
      await sql.query('commit');
    } catch (error) {
      await sql.query('rollback');
      throw new Error(`Migration ${file} failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  console.log(`Neon migrations up to date (${files.length} files discovered).`);
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
