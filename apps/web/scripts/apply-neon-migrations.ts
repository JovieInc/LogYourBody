// GitHub Actions runs this with Node/tsx; `server-only` throws outside Next.js.
import { Client, neonConfig } from '@neondatabase/serverless';
import * as dotenv from 'dotenv';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import WebSocket from 'ws';

type MigrationClient = {
  query: (queryText: string, values?: readonly unknown[]) => Promise<unknown>;
};

const migrationDirectory = path.resolve(process.cwd(), 'db/migrations');

export function assertDirectNeonMigrationConnection(connectionString: string): void {
  let databaseUrl: URL;
  try {
    databaseUrl = new URL(connectionString);
  } catch {
    throw new Error('DATABASE_URL must be a valid direct Neon PostgreSQL connection string.');
  }

  if (
    !['postgres:', 'postgresql:'].includes(databaseUrl.protocol) ||
    !databaseUrl.hostname.endsWith('.neon.tech') ||
    databaseUrl.hostname.includes('-pooler')
  ) {
    throw new Error('DATABASE_URL must be a direct Neon PostgreSQL connection string for migrations.');
  }
}

export async function applyNeonMigrations(
  client: MigrationClient,
  directory = migrationDirectory,
  log: (message: string) => void = console.log,
): Promise<number> {
  await client.query(`
    create table if not exists public.schema_migrations (
      version text primary key,
      applied_at timestamptz not null default now()
    )
  `);

  const files = (await fs.readdir(directory))
    .filter((file) => file.endsWith('.sql'))
    .sort();
  const applied = (await client.query(
    'select version from public.schema_migrations',
  )) as { rows: Array<{ version: string }> };
  const appliedVersions = new Set(applied.rows.map(({ version }) => version));

  for (const file of files) {
    const version = file.replace(/\.sql$/, '');
    if (appliedVersions.has(version)) continue;

    const contents = await fs.readFile(path.join(directory, file), 'utf8');
    log(`Applying ${file}`);
    try {
      await client.query('BEGIN');
      await client.query(contents);
      await client.query(
        `
        insert into public.schema_migrations (version)
        values ($1)
        on conflict (version) do nothing
      `,
        [version],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw new Error(`Migration ${file} failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  log(`Neon migrations up to date (${files.length} files discovered).`);
  return files.length;
}

async function main() {
  dotenv.config({ path: path.resolve(process.cwd(), '.env.local') });

  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL');
  assertDirectNeonMigrationConnection(connectionString);

  neonConfig.webSocketConstructor = WebSocket;
  const client = new Client(connectionString);
  await client.connect();

  try {
    await applyNeonMigrations(client);
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  void main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
