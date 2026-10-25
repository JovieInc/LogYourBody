/** Execute the real adapter and additive migration on the existing verifier's
 * disposable PostgreSQL16. No provider credentials or production URL are used. */
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { promisify } from 'node:util';
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonDatedOutcomes } from '../../src/lib/neon/dated-outcome-adapter';
import { datedOutcomeSchema, type DatedOutcomeEdit } from '../../src/lib/ports/dated-outcome';
import { requireNativeAccountAdmission } from '../../src/lib/ports/native-account-admission';

const execute = promisify(execFile);
const client: string[] = JSON.parse(process.argv[2]);
assert(
  client.includes('-h') && client[client.indexOf('-h') + 1].startsWith('/tmp/lyb-mutation-pg-'),
);
const quote = (value: unknown) =>
  value === null ? 'null' : "'" + String(value).replaceAll("'", "''") + "'";
async function sql(statement: string) {
  try {
    return (
      await execute(client[0], [...client.slice(1), '-v', 'VERBOSITY=verbose', '-c', statement], {
        timeout: 30_000,
      })
    ).stdout.trim();
  } catch (error) {
    const detail = (error as { stderr?: string }).stderr ?? '';
    throw Object.assign(new Error(detail), { code: detail.match(/ERROR:\s+([A-Z0-9]{5}):/)?.[1] });
  }
}
type Query = { statement: string; then: PromiseLike<unknown>['then'] };
async function rows(statements: string[]) {
  const output = await sql(
    'begin;\n' +
      statements
        .map(
          (statement) =>
            `select coalesce(json_agg(row_to_json(outcome_row)), '[]'::json) from (${statement}) outcome_row;`,
        )
        .join('\n') +
      '\ncommit;',
  );
  return output
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}
const database = {
  query(text: string, params: unknown[]): Query {
    const statement = text.replace(/\$(\d+)/g, (_, index: string) =>
      quote(params[Number(index) - 1]),
    );
    return {
      statement,
      then: (resolve, reject) =>
        rows([statement])
          .then((result) => result[0])
          .then(resolve, reject),
    };
  },
  transaction: (queries: Query[]) => rows(queries.map((q) => q.statement)),
} as unknown as NeonQueryFunction<false, false>;
const outcomes = createNeonDatedOutcomes(database);

async function main() {
  const subject = 'outcome-' + randomUUID(),
    ownerId = randomUUID();
  const seedProfile = {
    date_of_birth: '1990-01-01',
    training_inputs: { experience: 'returning', limitations: ['knee_pain'] },
  };
  await sql(
    `insert into app_users(id,identity_subject,profile_data) values(${quote(ownerId)},${quote(subject)},${quote(JSON.stringify(seedProfile))}::jsonb);`,
  );
  const migration = readFileSync(
    new URL('../migrations/20261025130000_dated_outcome.sql', import.meta.url),
    'utf8',
  );
  await sql(migration);
  await sql(migration); // Idempotent replay over a populated existing schema.
  assert.deepEqual(
    JSON.parse(await sql(`select profile_data from app_users where id=${quote(ownerId)};`)),
    seedProfile,
  );
  assert.equal(await outcomes.read(subject), null);
  const admission = requireNativeAccountAdmission(await outcomes.capture(subject));
  const value = datedOutcomeSchema.parse({
    outcome: { metric: 'body_fat_percentage', targetValue: 20 },
    outcomeDate: '2027-04-01',
    constraints: {
      availability: { sessionsPerWeek: 3, equipment: 'dumbbells' },
      travel: [{ start: '2027-01-01', end: '2027-01-07' }],
      maintenance: [],
    },
  });
  // External source is optional for the shared offline CI runner; local qualification
  // supplies the fixture read from Jovie main. It is never copied into this repository.
  if (process.env.LYB_LAUNCH_CONTRACT_PATH) {
    const fixture = JSON.parse(readFileSync(process.env.LYB_LAUNCH_CONTRACT_PATH, 'utf8'));
    assert.equal(fixture.schema, 'lyb-launch-contract/v1');
    assert.deepEqual(Object.keys(value).sort(), fixture.promise.requiredInputs.toSorted());
    assert(fixture.requiredPaths.some((p: { id: string }) => p.id === 'launch.deadline-replan'));
  }
  const first: DatedOutcomeEdit = { requestId: randomUUID(), previousRevision: null, value };
  const saved = { kind: 'saved', snapshot: { revision: first.requestId, value } };
  const count = async () =>
    Number(
      await sql(
        `select count(*) from dated_outcome_recompute_requests where owner_id=${quote(ownerId)};`,
      ),
    );
  const results = await Promise.all([
    outcomes.save(admission, first),
    outcomes.save(admission, first),
  ]);
  assert.deepEqual(results, [saved, saved]);
  assert.equal(await count(), 1);
  assert.deepEqual(await outcomes.read(subject), saved.snapshot);
  assert.equal(await outcomes.read('different-owner'), null);
  assert.deepEqual(await outcomes.exportForSubject('different-owner'), []);
  assert.equal((await outcomes.exportForSubject(subject)).length, 1);

  const dateEdit = {
    ...first,
    requestId: randomUUID(),
    previousRevision: first.requestId,
    value: { ...value, outcomeDate: '2027-05-01' },
  };
  assert.equal((await outcomes.save(admission, dateEdit)).kind, 'saved');
  assert.equal(await count(), 2);
  const constraintEdit = {
    ...dateEdit,
    requestId: randomUUID(),
    previousRevision: dateEdit.requestId,
    value: {
      ...dateEdit.value,
      constraints: {
        ...value.constraints,
        availability: { sessionsPerWeek: 2 as const },
        maintenance: [{ start: '2027-02-01', end: '2027-02-14' }],
      },
    },
  };
  assert.equal((await outcomes.save(admission, constraintEdit)).kind, 'saved');
  assert.equal(await count(), 3);
  const inputs = JSON.parse(
    await sql(`select profile_data->'training_inputs' from app_users where id=${quote(ownerId)};`),
  );
  assert.deepEqual(inputs, {
    experience: 'returning',
    limitations: ['knee_pain'],
    sessionsPerWeek: 2,
    goal: 'body_fat_percentage: 20',
    goalDate: '2027-05-01T00:00:00Z',
  });
  const requestInputs = JSON.parse(
    await sql(
      `select plan_inputs from dated_outcome_recompute_requests where request_id=${quote(constraintEdit.requestId)};`,
    ),
  );
  assert.equal(requestInputs.goalDate, inputs.goalDate);
  assert.equal(requestInputs.sessionsPerWeek, 2);
  assert.equal(
    (await outcomes.save(admission, { ...constraintEdit, value })).kind,
    'request_conflict',
  );
  assert.equal(
    (await outcomes.save(admission, { ...first, requestId: randomUUID() })).kind,
    'revision_conflict',
  );
  assert.equal(await count(), 3);
  // Old duplicate receipts acknowledge the old edit without rolling back the latest value.
  assert.deepEqual(await outcomes.save(admission, first), saved);
  assert.equal((await outcomes.read(subject))?.revision, constraintEdit.requestId);
  assert.equal(
    await sql(`select count(*) from native_records where user_subject=${quote(subject)};`),
    '0',
  );

  // A failure between the outcome update and queue insert must roll back both and all inputs.
  await sql(`create function outcome_injected_failure() returns trigger language plpgsql as $$begin raise exception 'injected outcome failure'; end;$$;
    create trigger outcome_fail before insert on dated_outcome_recompute_requests for each row execute function outcome_injected_failure();`);
  const failing = {
    ...constraintEdit,
    requestId: randomUUID(),
    previousRevision: constraintEdit.requestId,
    value: { ...constraintEdit.value, outcomeDate: '2028-01-01' },
  };
  await assert.rejects(outcomes.save(admission, failing), /injected outcome failure/);
  assert.equal((await outcomes.read(subject))?.revision, constraintEdit.requestId);
  assert.equal(await count(), 3);
  await sql('drop trigger outcome_fail on dated_outcome_recompute_requests;');

  // Two competing date/constraint changes admit only one next revision/request.
  const competing = { ...failing, requestId: randomUUID() };
  const concurrent = await Promise.all([
    outcomes.save(admission, failing),
    outcomes.save(admission, competing),
  ]);
  assert.deepEqual(concurrent.map((r) => r.kind).sort(), ['revision_conflict', 'saved']);
  assert.equal(await count(), 4);

  await sql(`delete from app_users where id=${quote(ownerId)};`);
  assert.equal(await count(), 0);
  await sql(`insert into app_users(identity_subject) values(${quote(subject)});`);
  await assert.rejects(outcomes.save(admission, first), /account_changed/);
  assert.equal(await outcomes.read(subject), null);
  console.log(
    'PASS dated outcome: populated migration/replay; external contract fields; concurrent retry dedupe; date/constraints inputs; stale/conflicting writes; rollback; owner isolation; delete/recreate fence; no engine writes',
  );
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
