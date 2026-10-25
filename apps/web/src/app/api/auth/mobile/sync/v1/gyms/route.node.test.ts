/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createGymRegistryHandlers } from './route-handlers';
import { NativeAccountAdmissionError } from '@/lib/ports/native-account-admission';

const id = '11111111-1111-4111-8111-111111111111';
const gym = { id, name: 'Home', region: null, equipment: [], preferredMachines: ['Chest press'] };
const admission = { subject: 'owner-a', ownerId: id };
function request(method: string, body?: unknown) {
  return new NextRequest('http://localhost/api/auth/mobile/sync/v1/gyms', {
    method,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
function harness() {
  const authenticate = jest.fn(async () => ({ sub: 'owner-a' }));
  const registry = {
    list: jest.fn(async () => [gym]),
    save: jest.fn(async () => true),
    remove: jest.fn(),
  };
  const accounts = { capture: jest.fn(async () => admission) };
  return {
    ...createGymRegistryHandlers({ authenticate, registry, accounts }),
    registry,
    accounts,
    authenticate,
  };
}

describe('gym registry bearer boundary', () => {
  it('scopes reads and every mutation to the authenticated account, preserving empty inventory', async () => {
    const h = harness();
    expect(await (await h.GET(request('GET'))).json()).toEqual({ gyms: [gym] });
    expect(h.registry.list).toHaveBeenCalledWith('owner-a');
    expect(await (await h.POST(request('POST', gym))).json()).toEqual({ gym });
    expect(h.registry.save).toHaveBeenCalledWith(admission, gym);
    expect((await h.DELETE(request('DELETE', { id }))).status).toBe(200);
    expect(h.registry.remove).toHaveBeenCalledWith(admission, id);
  });
  it.each(['GET', 'POST', 'DELETE'] as const)(
    'rejects unauthenticated %s before storage',
    async (method) => {
      const h = harness();
      h.authenticate.mockResolvedValue(null as never);
      expect((await h[method](request(method, method === 'GET' ? undefined : gym))).status).toBe(
        401,
      );
      expect(h.accounts.capture).not.toHaveBeenCalled();
      expect(h.registry.list).not.toHaveBeenCalled();
      expect(h.registry.save).not.toHaveBeenCalled();
      expect(h.registry.remove).not.toHaveBeenCalled();
    },
  );
  it.each([
    { ...gym, user_subject: 'owner-b' },
    { ...gym, name: ' ' },
    { ...gym, equipment: ['assumed_full_gym'] },
    { ...gym, region: 'x'.repeat(101) },
    { ...gym, preferredMachines: [''] },
  ])('rejects invalid or spoofed inventory before writes', async (body) => {
    const h = harness();
    expect((await h.POST(request('POST', body))).status).toBe(400);
    expect(h.registry.save).not.toHaveBeenCalled();
  });
  it('accepts native omitted optional region without supplying equipment', async () => {
    const h = harness();
    const { region: _region, ...body } = gym;
    expect((await h.POST(request('POST', body))).status).toBe(200);
    expect(h.registry.save).toHaveBeenCalledWith(admission, gym);
  });
  it('does not acknowledge a conflicting gym ID or changed account', async () => {
    const h = harness();
    h.registry.save.mockResolvedValue(false);
    expect((await h.POST(request('POST', gym))).status).toBe(409);
    h.registry.save.mockRejectedValue(new NativeAccountAdmissionError('account_changed'));
    expect((await h.POST(request('POST', gym))).status).toBe(409);
  });
});
