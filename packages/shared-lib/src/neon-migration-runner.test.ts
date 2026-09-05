import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

import {
  applyNeonMigrations,
  assertDirectNeonMigrationConnection,
} from '../../../apps/web/scripts/apply-neon-migrations';

class RecordingClient {
  readonly calls: Array<{ query: string; values?: readonly unknown[] }> = [];

  async query(query: string, values?: readonly unknown[]): Promise<unknown> {
    this.calls.push({ query, values });

    if (query === 'select version from public.schema_migrations') {
      return { rows: [] };
    }

    return { rows: [] };
  }
}

describe('Neon migration runner', () => {
  const tempDirs: string[] = [];

  afterEach(() => {
    for (const directory of tempDirs.splice(0)) {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it('runs a complete multi-statement migration inside one transaction', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'lyb-neon-migrations-'));
    tempDirs.push(directory);
    const migration = 'create table example (id integer);\ninsert into example values (1);\n';
    writeFileSync(join(directory, '20260905120000_multi_statement.sql'), migration);
    const client = new RecordingClient();

    const count = await applyNeonMigrations(client, directory, () => undefined);

    expect(count).toBe(1);
    expect(client.calls.map(({ query }) => query)).toEqual([
      expect.stringContaining('create table if not exists public.schema_migrations'),
      'select version from public.schema_migrations',
      'BEGIN',
      migration,
      expect.stringContaining('insert into public.schema_migrations'),
      'COMMIT',
    ]);
    expect(client.calls[4]?.values).toEqual(['20260905120000_multi_statement']);
  });

  it('requires a direct Neon endpoint for migration execution', () => {
    expect(() =>
      assertDirectNeonMigrationConnection(
        'postgresql://user:password@ep-example-123.us-west-2.aws.neon.tech/neondb',
      ),
    ).not.toThrow();
    expect(() =>
      assertDirectNeonMigrationConnection(
        'postgresql://user:password@ep-example-123-pooler.us-west-2.aws.neon.tech/neondb',
      ),
    ).toThrow('direct Neon');
    expect(() =>
      assertDirectNeonMigrationConnection('postgresql://user:password@db.example.invalid/postgres'),
    ).toThrow('direct Neon');
  });
});
