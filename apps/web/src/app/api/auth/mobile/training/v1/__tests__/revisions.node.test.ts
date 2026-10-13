/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createTrainingRevisionHandlers } from '../revision-route-handlers';
import { createTrainingRouteHandlers } from '../route-handlers';
import { revisionHarness, proposalBody, decisionBody } from '@/lib/training/revisions.testing';
import { TRAINING_CONSENT_VERSION } from '@/lib/training/types';

const now = () => new Date('2026-10-10T12:00:00Z');
function request(method = 'GET', body?: unknown, query = '') {
  return new NextRequest(
    'http://localhost:3000/api/auth/mobile/training/v1/program-proposals' + query,
    {
      method,
      ...(body === undefined
        ? {}
        : { body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' } }),
    },
  );
}
function harness() {
  const h = revisionHarness();
  const dependencies = {
    revisions: h.port,
    authenticate: jest.fn(async () => ({ sub: 'owner' }) as never),
    reserveRequest: jest.fn(
      async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }) as const,
    ),
    now,
    enabled: jest.fn(() => true),
  };
  return { ...h, dependencies, handlers: createTrainingRevisionHandlers(dependencies) };
}
describe('training proposal HTTP boundary', () => {
  it('keeps unauthorized, default-off and rate-limited callers from storage', async () => {
    const h = harness();
    h.dependencies.authenticate.mockResolvedValueOnce(null as never);
    expect((await h.handlers.GET(request())).status).toBe(401);
    h.dependencies.enabled.mockReturnValueOnce(false);
    expect((await h.handlers.POST(request('POST', proposalBody))).status).toBe(404);
    h.dependencies.reserveRequest.mockResolvedValueOnce({
      allowed: false,
      retryAfterSeconds: 30,
    } as never);
    const limited = await h.handlers.GET(request());
    expect(limited.status).toBe(429);
    expect(limited.headers.get('Retry-After')).toBe('30');
    expect(h.port.readContext).not.toHaveBeenCalled();
    expect(h.port.createProposal).not.toHaveBeenCalled();
  });
  it('reads pure context, previews, applies and reads back a durable decision', async () => {
    const h = harness();
    const context = await h.handlers.GET(request());
    expect(await context.json()).toEqual({
      version: 1,
      generation: 0,
      headRevision: null,
      supportedIntent: 'initial_enrollment',
      supportedBaseline: true,
    });
    expect(h.proposals.size).toBe(0);
    const created = await h.handlers.POST(request('POST', proposalBody));
    expect(created.status).toBe(201);
    const { stored } = await created.json();
    const applied = await h.handlers.PATCH(request('PATCH', decisionBody(stored.proposal.id)));
    expect(applied.status).toBe(200);
    const { receipt } = await applied.json();
    expect(receipt.status).toBe('applied');
    const read = await h.handlers.GET(request('GET', undefined, '?id=' + stored.proposal.id));
    expect(await read.json()).toMatchObject({ stored: { status: 'applied', receipt } });
    expect(read.headers.get('Cache-Control')).toBe('no-store');
  });
  it('returns explicit rejection with no applied copy and typed conflicts for changed retries', async () => {
    const h = harness();
    const created = await (await h.handlers.POST(request('POST', proposalBody))).json();
    const rejected = await h.handlers.PATCH(
      request('PATCH', decisionBody(created.stored.proposal.id, 'reject')),
    );
    expect(await rejected.json()).toMatchObject({
      receipt: { status: 'rejected', setup: null, revisionId: null },
    });
    const changed = await h.handlers.POST(
      request('POST', { ...proposalBody, reason: 'different reason' }),
    );
    expect(changed.status).toBe(409);
    expect(await changed.json()).toEqual({ version: 1, error: 'request_conflict' });
    const unsupported = await h.handlers.POST(
      request('POST', { ...proposalBody, intent: { kind: 'trainer_edit' } }),
    );
    expect(unsupported.status).toBe(400);
  });
  it('does not fake success or generic record writes when migration/atomic capability is unavailable', async () => {
    const h = harness();
    jest.mocked(h.port.readContext).mockRejectedValueOnce(new Error('function does not exist'));
    const response = await h.handlers.POST(request('POST', proposalBody));
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ version: 1, error: 'training_unavailable' });
    expect((await h.records.pull('owner', 'training_feedback')).records).toHaveLength(0);
  });
});

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => (resolve = r));
  return { promise, resolve };
}
describe('in-flight legacy enrollment consent fence', () => {
  function legacy() {
    const h = revisionHarness();
    const entered = deferred<void>();
    const release = deferred<void>();
    const users = {
      getUser: jest.fn(async () => {
        entered.resolve();
        await release.promise;
        return { profileData: { date_of_birth: '1990-01-01' } };
      }),
    };
    jest.mocked(h.port.storeLegacySetup).mockImplementation(async (subject, setup, context) => {
      if (context.generation !== h.context.generation || context.ownerId !== h.context.ownerId)
        throw new Error('stale context');
      await h.records.push(subject, 'training_feedback', [
        { ...setup, record_type: 'program_setup' },
      ]);
      h.context.generation += 1;
    });
    jest.mocked(h.port.revoke).mockImplementation(async (subject) => {
      h.context.generation += 1;
      const rows = await h.records.pull(subject, 'training_feedback');
      return (
        await h.records.remove(
          subject,
          'training_feedback',
          rows.records.map((r) => r.id),
        )
      ).deleted_ids.length;
    });
    const handlers = createTrainingRouteHandlers({
      records: h.records,
      revisions: h.port,
      users: users as never,
      authenticate: async () => ({ sub: 'owner' }) as never,
      enabled: () => true,
      now,
      createId: () => proposalBody.requestId,
      reserveRequest: async () => ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }),
    });
    return { ...h, handlers, entered, release };
  }
  const body = {
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek: 2,
    equipment: 'dumbbells',
  };
  it('held profile lookup cannot restore enrollment after revoke returns', async () => {
    const h = legacy();
    const pending = h.handlers.enroll(request('POST', body));
    await h.entered.promise;
    expect((await h.handlers.revoke(request('DELETE'))).status).toBe(200);
    h.release.resolve();
    expect((await pending).status).toBe(503);
    expect((await h.records.pull('owner', 'training_feedback')).records).toHaveLength(0);
    expect(h.port.storeLegacySetup).toHaveBeenCalledWith(
      'owner',
      expect.objectContaining({ consentVersion: TRAINING_CONSENT_VERSION }),
      expect.objectContaining({ generation: 0 }),
    );
  });
  it('held enrollment cannot cross delete/recreate with the same consent generation', async () => {
    const h = legacy();
    const pending = h.handlers.enroll(request('POST', body));
    await h.entered.promise;
    const oldOwner = h.context.ownerId;
    await h.records.deleteAllForSubject('owner');
    h.context.ownerId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    expect(h.context.generation).toBe(0);
    h.release.resolve();
    expect((await pending).status).toBe(503);
    expect((await h.records.pull('owner', 'training_feedback')).records).toHaveLength(0);
    expect(h.port.storeLegacySetup).toHaveBeenCalledWith(
      'owner',
      expect.anything(),
      expect.objectContaining({ ownerId: oldOwner, generation: 0 }),
    );
    expect((await h.handlers.enroll(request('POST', body))).status).toBe(201);
  });
  it('enrollment first is fully removed by a later revoke; new explicit request captures fresh consent', async () => {
    const h = legacy();
    h.release.resolve();
    expect((await h.handlers.enroll(request('POST', body))).status).toBe(201);
    expect((await h.handlers.revoke(request('DELETE'))).status).toBe(200);
    expect(
      (await h.records.pull('owner', 'training_feedback')).records.every((r) => r.deleted_at),
    ).toBe(true);
    expect((await h.handlers.enroll(request('POST', body))).status).toBe(201);
    expect(
      (await h.records.pull('owner', 'training_feedback')).records.filter((r) => !r.deleted_at),
    ).toHaveLength(1);
  });
});
