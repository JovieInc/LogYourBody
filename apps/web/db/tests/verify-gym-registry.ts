/** Exercise the actual adapter against the verifier's disposable PostgreSQL16.
 * Only transport is replaced; queries and transaction boundaries are unchanged. */
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { promisify } from 'node:util';
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonGymRegistry } from '../../src/lib/neon/gym-registry-adapter';
import { CATALOG_EQUIPMENT } from '../../src/lib/training/catalog';

const client: string[] = JSON.parse(process.argv[2]);
assert(
  client.includes('-h') && client[client.indexOf('-h') + 1].startsWith('/tmp/lyb-mutation-pg-'),
);
const execute = promisify(execFile);
async function sql(statement: string) {
  const { stdout } = await execute(client[0], [...client.slice(1), '-c', statement], {
    timeout: 30_000,
  });
  return stdout.trim().split('\n').at(-1)!;
}
const quote = (value: unknown): string => {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array[' + value.map(quote).join(',') + ']::text[]';
  return "'" + String(value).replaceAll("'", "''") + "'";
};
type Query = { statement: string; values: unknown[] };
const bind = ({ statement, values }: Query) =>
  statement.replace(/\$(\d+)/g, (_, index: string) => quote(values[Number(index) - 1]));
const rows = (statement: string) =>
  `select coalesce(json_agg(row_to_json(gym_row)), '[]'::json) from (${statement}) gym_row`;
let afterAdmission: (() => Promise<void>) | undefined;
const database = {
  query(statement: string, values: unknown[]) {
    return {
      statement,
      values,
      then(resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) {
        return sql(rows(bind({ statement, values })))
          .then(async (value) => {
            const hook = afterAdmission;
            afterAdmission = undefined;
            if (hook) await hook();
            return JSON.parse(value);
          })
          .then(resolve, reject);
      },
    };
  },
  async transaction(queries: Query[]) {
    const last = queries.length - 1;
    const statements = queries.map((query, index) =>
      index === last ? rows(bind(query)) : bind(query),
    );
    const result = await sql('begin; ' + statements.join('; ') + '; commit;');
    return queries.map((_, index) => (index === last ? JSON.parse(result) : []));
  },
} as unknown as NeonQueryFunction<false, false>;

async function main() {
  const registry = createNeonGymRegistry(database);
  const subject = 'gym-' + randomUUID();
  const other = 'gym-' + randomUUID();
  const owner = randomUUID();
  await sql(`insert into app_users(id,identity_provider,identity_subject) values
    (${quote(owner)},'jovie',${quote(subject)}),(${quote(randomUUID())},'jovie',${quote(other)});`);
  assert.deepEqual(await registry.sync(subject), []);
  const gym = {
    id: randomUUID(),
    name: 'Confirmed',
    coarseRegion: null,
    equipment: ['dumbbells' as const],
    preferredMachines: ['My machine'],
  };
  const first = { gym, deleted: false };
  assert.deepEqual(await registry.sync(subject, [first]), [first]);
  assert.deepEqual(await registry.sync(other), []);
  // A stolen UUID cannot overwrite or read another account's gym.
  try {
    await registry.sync(other, [{ gym: { ...gym, name: 'Stolen' }, deleted: false }]);
  } catch {
    // Forced RLS may reject the conflicting insert before the owner predicate.
  }
  assert.deepEqual(await registry.sync(subject), [first]);
  assert.deepEqual(await registry.sync(other), []);
  // Every catalog item must be accepted by the SQL inventory constraint.
  // A new catalog item without a migration makes this drift check fail.
  const allEquipment = { gym: { ...gym, equipment: [...CATALOG_EQUIPMENT] }, deleted: false };
  assert.deepEqual(await registry.sync(subject, [allEquipment]), [allEquipment]);
  const updated = { gym: { ...gym, name: 'Edited', equipment: [] }, deleted: false };
  assert.deepEqual(await registry.sync(subject, [updated]), [updated]);
  const deleted = { ...updated, deleted: true };
  assert.deepEqual(await registry.sync(subject, [deleted]), [deleted]);
  assert.deepEqual(await registry.sync(subject, [first]), [deleted]);
  await sql(`delete from app_users where id=${quote(owner)};`);
  assert.equal(await sql(`select count(*) from gyms where owner_id=${quote(owner)};`), '0');
  await assert.rejects(registry.sync(subject, [first]));
  const replacementOwner = randomUUID();
  await sql(`insert into app_users(id,identity_provider,identity_subject)
    values (${quote(replacementOwner)},'jovie',${quote(subject)});`);
  afterAdmission = async () => {
    await sql(`delete from app_users where id=${quote(replacementOwner)};
      insert into app_users(id,identity_provider,identity_subject)
      values (${quote(randomUUID())},'jovie',${quote(subject)});`);
  };
  await assert.rejects(registry.sync(subject, [first]));
  assert.deepEqual(await registry.sync(subject), []);
  console.log(
    'Gym registry: actual adapter CRUD, catalog/schema drift, empty inventory, owner isolation, tombstones, account cascade and stale admission passed',
  );
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
