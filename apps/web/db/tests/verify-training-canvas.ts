/** Real canvas adapter + handler qualification on the verifier's disposable PostgreSQL16.
 * Only the Neon wire transport is replaced with psql; queries, transactions, migrations,
 * request admission, and service-generated payloads execute unchanged. No provider acceptance.
 */
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { promisify } from 'node:util';
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { NextRequest } from 'next/server';
import { createCanvasRouteHandlers } from '../../src/app/api/auth/mobile/training/v1/canvas-route-handlers';
import { captureNativeAccountAdmission } from '../../src/lib/neon/native-account-admission';
import { createNeonCanvasLedger } from '../../src/lib/neon/training-canvas-adapter';
import { requireNativeAccountAdmission } from '../../src/lib/ports/native-account-admission';
import {
  decideCanvasProposal,
  memoryCanvasPort,
  proposeCanvasEdit,
  interpretPlanUtterance,
} from '../../src/lib/training/mesocycle-canvas';

const execute = promisify(execFile);
const client: string[] = JSON.parse(process.argv[2]);
// The parent supplies a socket-only disposable client, never a connection URL.
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
const query = (text: string, params: unknown[]): Query => {
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
};
async function rows(statements: string[]) {
  const output = await sql(
    'begin;\n' +
      statements
        .map(
          (statement) =>
            `select coalesce(json_agg(row_to_json(canvas_result_row)), '[]'::json) from (${statement}) canvas_result_row;`,
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
  query,
  transaction: (queries: Query[]) => rows(queries.map((item) => item.statement)),
} as unknown as NeonQueryFunction<false, false>;
const checks: string[] = [];
function passed(name: string) {
  checks.push(name);
  console.log('PASS canvas ' + name);
}
const now = '2026-10-14T18:00:00.000Z';
async function owner(subject = 'canvas-' + randomUUID()) {
  await sql(
    `insert into app_users(id,identity_provider,identity_subject) values(${quote(randomUUID())},'jovie',${quote(subject)});`,
  );
  const admission = requireNativeAccountAdmission(
    await captureNativeAccountAdmission(database, subject),
  );
  return { subject, admission, port: createNeonCanvasLedger(admission, database) };
}
async function payloads(subject: string) {
  const port = memoryCanvasPort();
  const proposal = await proposeCanvasEdit(port, subject, {
    requestId: randomUUID(),
    expectedWrite: null,
    now,
    operation: interpretPlanUtterance('Build a 4-week hypertrophy plan for a full gym')!,
  });
  // Use the same utterance interpreter as the actual handler for valid engine output.
  assert.equal(proposal.kind, 'proposed');
  const proposed = (await port.load(subject))!;
  assert.equal(proposed.write, 1);
  const applied = await decideCanvasProposal(port, subject, {
    requestId: randomUUID(),
    expectedWrite: 1,
    now,
    proposalId: proposed.proposals[0].proposal.id,
    decision: 'apply',
  });
  assert.equal(applied.kind, 'decided');
  return { proposed, applied: (await port.load(subject))! };
}
async function changed(work: () => Promise<unknown>) {
  await assert.rejects(work, { code: 'account_changed' });
}
function handlers() {
  return createCanvasRouteHandlers({
    authenticate: async (request) =>
      request.headers.get('authorization') === 'Bearer synthetic' ? { sub: subject } : null,
    accounts: { capture: (value) => captureNativeAccountAdmission(database, value) },
    ledgerForAccount: (admission) => createNeonCanvasLedger(admission, database),
    reserveRequest: async () => ({ allowed: true, remainingToday: 10, remainingInWindow: 10 }),
    now: () => new Date(now),
    enabled: () => true,
  });
}
let subject: string;
async function main() {
  assert.equal(
    await sql("select to_regprocedure('public.training_canvas_save(text,bigint,jsonb)') is null;"),
    't',
  );
  const h = await owner();
  const payload = await payloads(h.subject);
  assert.equal(await h.port.load(h.subject), null);
  assert.deepEqual(await h.port.save(h.subject, null, payload.proposed), { kind: 'saved' });
  assert.deepEqual(await h.port.save(h.subject, null, payload.proposed), { kind: 'stale' });
  assert.deepEqual(await h.port.load(h.subject), payload.proposed);
  passed('legitimate first save/readback and duplicate first-save refusal');
  const outcomes = await Promise.all([
    h.port.save(h.subject, 1, payload.applied),
    h.port.save(h.subject, 1, payload.applied),
  ]);
  assert.deepEqual(outcomes.map((value) => value.kind).sort(), ['saved', 'stale']);
  assert.deepEqual(await h.port.load(h.subject), payload.applied);
  passed('concurrent CAS has one winner and exact applied readback');
  await changed(() => h.port.load('foreign-' + h.subject));
  await changed(() => h.port.save('foreign-' + h.subject, null, payload.proposed));
  passed('admitted adapter cannot cross subjects');
  await sql(`create function fail_canvas_update() returns trigger language plpgsql as $$ begin raise exception 'injected canvas SQL failure'; end; $$;
    create trigger fail_canvas_update before update on training_canvas_ledgers for each row execute function fail_canvas_update();`);
  await assert.rejects(
    () => h.port.save(h.subject, 2, { ...payload.applied, write: 3 }),
    /injected canvas SQL failure/,
  );
  assert.deepEqual(await h.port.load(h.subject), payload.applied);
  await sql(
    'drop trigger fail_canvas_update on training_canvas_ledgers; drop function fail_canvas_update();',
  );
  passed('real SQL error rolls back without successful acknowledgement or fallback');

  for (const fresh of [false, true]) {
    const old = await owner();
    const held = await payloads(old.subject);
    if (fresh) await old.port.save(old.subject, null, held.proposed);
    await sql(`delete from app_users where identity_subject=${quote(old.subject)};`);
    assert.equal(
      await sql(
        `select count(*) from training_canvas_ledgers where user_subject=${quote(old.subject)};`,
      ),
      '0',
    );
    await changed(() => old.port.save(old.subject, null, held.proposed));
    const replacement = await owner(old.subject);
    const distinct = await payloads(old.subject);
    if (fresh)
      assert.deepEqual(await replacement.port.save(old.subject, null, distinct.proposed), {
        kind: 'saved',
      });
    await changed(() =>
      old.port.save(old.subject, fresh ? 1 : null, fresh ? held.applied : held.proposed),
    );
    // Also call the actual function directly: no adapter-only fence can mask an unsafe SQL path.
    await assert.rejects(
      () =>
        sql(`select training_canvas_save(${quote(old.subject)},${quote(old.admission.ownerId)}::uuid,
      ${fresh ? 1 : 'null'},${quote(JSON.stringify(fresh ? held.applied : held.proposed))}::jsonb);`),
      { code: 'LYB01' },
    );
    await changed(() => old.port.load(old.subject));
    assert.deepEqual(await replacement.port.load(old.subject), fresh ? distinct.proposed : null);
    assert.deepEqual(
      await replacement.port.save(
        old.subject,
        fresh ? 1 : null,
        fresh ? distinct.applied : distinct.proposed,
      ),
      { kind: 'saved' },
    );
    passed(
      fresh
        ? 'stale apply cannot overwrite recreated owner at matching write 1'
        : 'stale first proposal cannot populate recreated empty ledger',
    );
  }

  // Hold the actual handler at request.json after canonical admission, then recreate.
  for (const fresh of [false, true]) {
    const old = await owner();
    subject = old.subject;
    const initial = await payloads(subject);
    if (fresh) await old.port.save(subject, null, initial.proposed);
    const route = handlers();
    let entered!: () => void, release!: () => void;
    const enteredBody = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const released = new Promise<void>((resolve) => {
      release = resolve;
    });
    const request = new NextRequest('http://localhost/api/auth/mobile/training/v1/canvas', {
      method: 'POST',
      headers: { authorization: 'Bearer synthetic' },
    });
    request.json = async () => {
      entered();
      await released;
      return fresh
        ? {
            action: 'decide',
            decision: 'apply',
            proposalId: initial.proposed.proposals[0].proposal.id,
            expectedWrite: 1,
          }
        : {
            action: 'submit',
            transcript: 'Build a 4-week hypertrophy plan for a full gym',
            expectedWrite: null,
          };
    };
    const pending = route.POST(request);
    await enteredBody;
    await sql(`delete from app_users where identity_subject=${quote(subject)};`);
    const replacement = await owner(subject);
    const distinct = await payloads(subject);
    if (fresh) await replacement.port.save(subject, null, distinct.proposed);
    release();
    const response = await pending;
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error, 'account_changed');
    assert.deepEqual(await replacement.port.load(subject), fresh ? distinct.proposed : null);
    passed(
      fresh
        ? 'held handler apply cannot adopt recreated ledger'
        : 'held handler first proposal cannot adopt recreated owner',
    );
  }
  const sources = [
    'db/tests/verify-training-canvas.ts',
    'src/lib/neon/training-canvas-adapter.ts',
    'src/lib/neon/native-account-admission.ts',
    'src/app/api/auth/mobile/training/v1/canvas-route-handlers.ts',
    'db/migrations/20261014180000_training_canvas_ledger.sql',
  ];
  console.log(
    JSON.stringify({
      canvasChecks: checks,
      sourceSha256: Object.fromEntries(
        sources.map((path) => [
          path,
          createHash('sha256')
            .update(readFileSync(new URL('../../' + path, import.meta.url)))
            .digest('hex'),
        ]),
      ),
    }),
  );
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
