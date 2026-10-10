/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createTrainingRouteHandlers } from '@/app/api/auth/mobile/training/v1/route-handlers';
import { handleMcpRequest } from '@/lib/mcp/handler';
import { LYB_MCP_SCOPES } from '@/lib/mcp/contract';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';

const subject = 'owner';
const now = new Date('2026-01-10T12:00:00Z');
async function fixture() {
  const records = new MemoryTrainingRecords();
  await storeProgramSetup({
    records,
    subject,
    now,
    createId: () => '11111111-1111-4111-8111-111111111111',
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'dumbbells',
    },
  });
  const result = await getOrCreateNextWorkout({ records, subject, now });
  if (result.kind !== 'workout') throw new Error('fixture');
  const reserveRequest = async () => ({
    allowed: true as const,
    remainingInWindow: 9,
    remainingToday: 99,
  });
  const handlers = createTrainingRouteHandlers({
    records,
    authenticate: async () => ({ sub: subject }) as never,
    users: {} as never,
    enabled: () => true,
    reserveRequest,
    now: () => now,
    createId: () => '22222222-2222-4222-8222-222222222222',
  });
  let enter!: () => void;
  let release!: () => void;
  const entered = new Promise<void>((r) => {
    enter = r;
  });
  const gate = new Promise<void>((r) => {
    release = r;
  });
  const commit = records.trainingMutations.commit.bind(records.trainingMutations);
  records.trainingMutations.commit = async (input) => {
    enter();
    await gate;
    return commit(input);
  };
  return {
    records,
    handlers,
    session: result.session,
    entered,
    release,
    reserveRequest,
    restoreCommit: () => {
      records.trainingMutations.commit = commit;
    },
  };
}
const request = (method: string, body?: unknown) =>
  new NextRequest('http://localhost/api/auth/mobile/training/v1/test', {
    method,
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
describe('training stale mutation receipts', () => {
  it.each(['mobile', 'MCP'] as const)(
    '%s rejects an identical feedback acknowledgement from a replaced owner',
    async (caller) => {
      const h = await fixture();
      h.restoreCommit();
      const feedback = { soreness: 2, pump: 2, performance: 'stable', jointPain: 0 };
      const body = { sessionId: h.session.id, ...feedback };
      expect((await h.handlers.feedback(request('POST', body))).status).toBe(201);
      const original = await h.records.listAll(subject);
      let enter!: () => void;
      let release!: () => void;
      const entered = new Promise<void>((r) => {
        enter = r;
      });
      const gate = new Promise<void>((r) => {
        release = r;
      });
      const pull = h.records.pull.bind(h.records);
      let feedbackReads = 0;
      h.records.pull = async (...args) => {
        const snapshot = await pull(...args);
        if (args[1] === 'training_feedback' && ++feedbackReads === (caller === 'MCP' ? 2 : 1)) {
          enter();
          await gate;
        }
        return snapshot;
      };
      const operation =
        caller === 'mobile'
          ? h.handlers.feedback(request('POST', body))
          : handleMcpRequest({
              body: {
                jsonrpc: '2.0',
                id: 1,
                method: 'tools/call',
                params: { name: 'log_session_feedback', arguments: feedback },
              },
              principal: {
                subject,
                scopes: new Set([LYB_MCP_SCOPES.trainingRead, LYB_MCP_SCOPES.trainingWrite]),
                clientId: 'synthetic',
              },
              deps: {
                records: h.records,
                now: () => now,
                createId: () => '22222222-2222-4222-8222-222222222222',
                resourceUrl: 'http://localhost/api/mcp',
                reserveRequest: h.reserveRequest,
              },
            });
      await entered;
      await h.records.deleteAllForSubject(subject);
      h.records.recreateOwner(subject);
      for (const collection of ['training_feedback', 'training_sessions', 'logged_sets'] as const)
        await h.records.push(subject, collection, original[collection]);
      const replacement = await h.records.listAll(subject);
      release();
      const result = await operation;
      if (result instanceof Response) {
        expect(result.status).toBe(409);
        expect(await result.json()).toMatchObject({ error: 'training_context_changed' });
      } else {
        expect(result.body).toMatchObject({
          result: { isError: true, structuredContent: { code: 'training_context_changed' } },
        });
      }
      expect(await h.records.listAll(subject)).toEqual(replacement);
    },
  );

  it.each(['next', 'set', 'feedback'] as const)(
    'mobile %s returns409 after revoke wins',
    async (kind) => {
      const h = await fixture();
      const exercise = h.session.exercises[0]!;
      const response =
        kind === 'next'
          ? h.handlers.next(request('GET'))
          : kind === 'set'
            ? h.handlers.logSet(
                request('POST', {
                  sessionId: h.session.id,
                  exerciseId: exercise.id,
                  setNumber: 1,
                  reps: exercise.targetReps,
                  loadKg: exercise.targetLoadKg,
                  rir: exercise.targetRir,
                }),
              )
            : h.handlers.feedback(
                request('POST', {
                  sessionId: h.session.id,
                  soreness: 2,
                  pump: 2,
                  performance: 'stable',
                  jointPain: 0,
                }),
              );
      await h.entered;
      expect((await h.handlers.revoke(request('DELETE'))).status).toBe(200);
      h.release();
      const result = await response;
      expect(result.status).toBe(409);
      expect(await result.json()).toMatchObject({ error: 'training_context_changed' });
    },
  );
  it.each(['log_sets', 'log_session_feedback'])(
    'MCP %s reports a stale result instead of saved',
    async (name) => {
      const h = await fixture();
      const args =
        name === 'log_sets'
          ? {
              exercise: h.session.exercises[0]!.name,
              weightUnit: 'kg',
              sets: [{ reps: 10, load: 20, rir: 2 }],
            }
          : { soreness: 2, pump: 2, performance: 'stable', jointPain: 0 };
      const response = handleMcpRequest({
        body: { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } },
        principal: {
          subject,
          scopes: new Set([LYB_MCP_SCOPES.trainingRead, LYB_MCP_SCOPES.trainingWrite]),
          clientId: 'synthetic',
        },
        deps: {
          records: h.records,
          now: () => now,
          createId: () => '22222222-2222-4222-8222-222222222222',
          resourceUrl: 'http://localhost/api/mcp',
          reserveRequest: h.reserveRequest,
        },
      });
      await h.entered;
      expect((await h.handlers.revoke(request('DELETE'))).status).toBe(200);
      h.release();
      expect((await response).body).toMatchObject({
        result: { isError: true, structuredContent: { code: 'training_context_changed' } },
      });
    },
  );
});

describe('outer MCP request owner admission', () => {
  it.each(['log_sets', 'log_session_feedback'])(
    '%s cannot adopt a recreated owner after its outer snapshot',
    async (name) => {
      const h = await fixture();
      h.restoreCommit();
      const original = await h.records.listAll(subject);
      let enter!: () => void;
      let release!: () => void;
      const entered = new Promise<void>((r) => {
        enter = r;
      });
      const gate = new Promise<void>((r) => {
        release = r;
      });
      const pull = h.records.pull.bind(h.records);
      let first = true;
      h.records.pull = async (...args) => {
        const result = await pull(...args);
        if (first) {
          first = false;
          enter();
          await gate;
        }
        return result;
      };
      const args =
        name === 'log_sets'
          ? { exercise: h.session.exercises[0]!.name, sets: [{ reps: 10, rir: 2 }] }
          : { soreness: 2, pump: 2, performance: 'stable', jointPain: 0 };
      const response = handleMcpRequest({
        body: { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } },
        principal: {
          subject,
          scopes: new Set([LYB_MCP_SCOPES.trainingRead, LYB_MCP_SCOPES.trainingWrite]),
          clientId: 'synthetic',
        },
        deps: {
          records: h.records,
          now: () => now,
          createId: () => '22222222-2222-4222-8222-222222222222',
          resourceUrl: 'http://localhost/api/mcp',
          reserveRequest: h.reserveRequest,
        },
      });
      await entered;
      await h.records.deleteAllForSubject(subject);
      h.records.recreateOwner(subject);
      for (const collection of ['training_feedback', 'training_sessions', 'logged_sets'] as const)
        await h.records.push(subject, collection, original[collection]);
      const replacement = await h.records.listAll(subject);
      release();
      expect((await response).body).toMatchObject({
        result: { isError: true, structuredContent: { code: 'training_context_changed' } },
      });
      expect(await h.records.listAll(subject)).toEqual(replacement);
    },
  );
});

it('keeps one MCP admission across a multi-set batch after the first set returns', async () => {
  const h = await fixture();
  h.restoreCommit();
  const original = await h.records.listAll(subject);
  const capture = jest.spyOn(h.records.trainingMutations, 'captureAdmission');
  const commit = h.records.trainingMutations.commit.bind(h.records.trainingMutations);
  let enter!: () => void;
  let release!: () => void;
  const entered = new Promise<void>((r) => {
    enter = r;
  });
  const gate = new Promise<void>((r) => {
    release = r;
  });
  let first = true;
  h.records.trainingMutations.commit = async (input) => {
    const result = await commit(input);
    if (input.action === 'set_insert' && first) {
      first = false;
      enter();
      await gate;
    }
    return result;
  };
  const response = handleMcpRequest({
    body: {
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name: 'log_sets',
        arguments: {
          exercise: h.session.exercises[0]!.name,
          sets: [
            { reps: 10, rir: 2 },
            { reps: 10, rir: 2 },
          ],
        },
      },
    },
    principal: {
      subject,
      scopes: new Set([LYB_MCP_SCOPES.trainingRead, LYB_MCP_SCOPES.trainingWrite]),
      clientId: 'synthetic',
    },
    deps: {
      records: h.records,
      now: () => now,
      createId: () => '22222222-2222-4222-8222-222222222222',
      resourceUrl: 'http://localhost/api/mcp',
      reserveRequest: h.reserveRequest,
    },
  });
  await entered;
  await h.records.deleteAllForSubject(subject);
  h.records.recreateOwner(subject);
  for (const collection of ['training_feedback', 'training_sessions', 'logged_sets'] as const)
    await h.records.push(subject, collection, original[collection]);
  const replacement = await h.records.listAll(subject);
  release();
  expect((await response).body).toMatchObject({
    result: { isError: true, structuredContent: { code: 'training_context_changed' } },
  });
  expect(await h.records.listAll(subject)).toEqual(replacement);
  expect(capture).toHaveBeenCalledTimes(1);
});
