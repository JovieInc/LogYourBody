/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createDatedOutcomeHandlers } from '../route-handlers';
import type { DatedOutcomePort, DatedOutcomeEdit } from '@/lib/ports/dated-outcome';
import { NativeAccountAdmissionError } from '@/lib/ports/native-account-admission';

const value = {
  outcome: { metric: 'weight_kg' as const, targetValue: 80 },
  outcomeDate: '2027-04-01',
  constraints: { availability: {}, travel: [], maintenance: [] },
};
const edit: DatedOutcomeEdit = {
  requestId: '26800000-0000-4000-8000-000000000001',
  previousRevision: null,
  value,
};
const snapshot = { revision: edit.requestId, value };
const admission = { subject: 'owner-a', ownerId: '26800000-0000-4000-8000-000000000002' };
function fixture() {
  const outcomes = {
    capture: jest.fn().mockResolvedValue(admission),
    read: jest.fn().mockResolvedValue(snapshot),
    save: jest.fn().mockResolvedValue({ kind: 'saved', snapshot }),
  } satisfies DatedOutcomePort;
  const deps = {
    outcomes,
    authenticate: jest.fn().mockResolvedValue({ sub: 'owner-a' }),
    enabled: () => true,
  };
  return { deps, outcomes, handlers: createDatedOutcomeHandlers(deps) };
}
function request(method: 'GET' | 'PUT', body: unknown = edit) {
  return new NextRequest('http://localhost/api/auth/mobile/dated-outcome?owner=foreign', {
    method,
    ...(method === 'PUT' ? { body: JSON.stringify(body) } : {}),
  });
}
describe('dated outcome authenticated API', () => {
  it('reads only the token owner and forbids caching', async () => {
    const h = fixture();
    const response = await h.handlers.GET(request('GET'));
    expect(await response.json()).toEqual({ snapshot });
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(h.outcomes.read).toHaveBeenCalledWith('owner-a');
  });
  it('commits a complete edit using the captured account incarnation', async () => {
    const h = fixture();
    const response = await h.handlers.PUT(request('PUT'));
    expect(response.status).toBe(200);
    expect(h.outcomes.save).toHaveBeenCalledTimes(1);
    expect(h.outcomes.save).toHaveBeenCalledWith(admission, edit);
  });
  it('rejects unauthorized and disabled traffic before persistence', async () => {
    const h = fixture();
    h.deps.authenticate.mockResolvedValueOnce(null);
    expect((await h.handlers.PUT(request('PUT'))).status).toBe(401);
    h.deps.enabled = () => false;
    expect((await h.handlers.PUT(request('PUT'))).status).toBe(404);
    expect(h.outcomes.capture).not.toHaveBeenCalled();
    expect(h.outcomes.save).not.toHaveBeenCalled();
  });
  it('rejects malformed/foreign fields without queuing a request', async () => {
    const h = fixture();
    expect((await h.handlers.PUT(request('PUT', { ...edit, ownerId: 'foreign' }))).status).toBe(
      400,
    );
    expect(h.outcomes.save).not.toHaveBeenCalled();
  });
  it.each(['revision_conflict', 'request_conflict'])(
    'preserves %s as an explicit conflict',
    async (kind) => {
      const h = fixture();
      h.outcomes.save.mockResolvedValue({ kind });
      expect((await h.handlers.PUT(request('PUT'))).status).toBe(409);
    },
  );
  it('fails closed on account deletion and never recaptures ownership', async () => {
    const h = fixture();
    h.outcomes.save.mockRejectedValue(new NativeAccountAdmissionError('account_changed'));
    expect((await h.handlers.PUT(request('PUT'))).status).toBe(409);
    expect(h.outcomes.capture).toHaveBeenCalledTimes(1);
    expect(h.outcomes.save).toHaveBeenCalledTimes(1);
  });
});
