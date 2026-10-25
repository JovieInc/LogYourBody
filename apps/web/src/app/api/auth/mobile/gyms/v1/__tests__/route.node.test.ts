/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createGymRegistryHandlers } from '../route-handlers';
import { CATALOG_EQUIPMENT, EXERCISE_CATALOG } from '@/lib/training/catalog';

const gym = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  coarseRegion: null,
  equipment: ['dumbbells'],
  preferredMachines: [],
};
const record = { gym, deleted: false };
const sync = jest.fn();
const authenticate = jest.fn();
const enabled = jest.fn();
const reserveRequest = jest.fn();
const handlers = createGymRegistryHandlers({
  authenticate,
  enabled,
  reserveRequest,
  registry: { sync },
});
const request = (method = 'GET', body?: unknown, query = '') =>
  new NextRequest('http://localhost:3000/api/auth/mobile/gyms/v1' + query, {
    method,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
beforeEach(() => {
  jest.resetAllMocks();
  authenticate.mockResolvedValue({ sub: 'owner-a' });
  enabled.mockReturnValue(true);
  reserveRequest.mockResolvedValue({ allowed: true });
  sync.mockResolvedValue([record]);
});

it('requires authentication and rollout before reading or writing gyms', async () => {
  authenticate.mockResolvedValueOnce(null);
  expect((await handlers.GET(request())).status).toBe(401);
  enabled.mockReturnValue(false);
  expect((await handlers.POST(request('POST', { changes: [record] }))).status).toBe(404);
  expect(sync).not.toHaveBeenCalled();
});

it('scopes CRUD sync to the verified subject and never accepts owner or location input', async () => {
  expect((await handlers.POST(request('POST', { changes: [record] }))).status).toBe(200);
  expect(sync).toHaveBeenCalledWith('owner-a', [record]);
  for (const change of [
    { owner_id: 'owner-b' },
    { latitude: 1 },
    { equipment: ['invented'] },
    { name: ' ' },
  ]) {
    expect(
      (
        await handlers.POST(
          request('POST', { changes: [{ ...record, gym: { ...gym, ...change } }] }),
        )
      ).status,
    ).toBe(400);
  }
  expect((await handlers.POST(request('POST', { changes: [record, record] }))).status).toBe(400);
  const result = await handlers.POST(request('POST', { changes: [{ ...record, deleted: true }] }));
  expect(result.status).toBe(200);
  expect(sync).toHaveBeenLastCalledWith('owner-a', [{ ...record, deleted: true }]);
  expect(result.headers.get('Cache-Control')).toBe('no-store');
});

it('returns full owned snapshots without selecting a gym', async () => {
  const result = await handlers.GET(request());
  expect(await result.json()).toEqual({ version: 1, gyms: [record] });
  expect(sync).toHaveBeenCalledWith('owner-a');
});

it('accepts the native encoding that omits an optional region', async () => {
  const nativeGym = {
    id: gym.id,
    name: gym.name,
    equipment: gym.equipment,
    preferredMachines: gym.preferredMachines,
  };
  const result = await handlers.POST(
    request('POST', { changes: [{ gym: nativeGym, deleted: false }] }),
  );
  expect(result.status).toBe(200);
  expect(sync).toHaveBeenCalledWith('owner-a', [record]);
});

it('honors rate limits and reports storage failures without a false acknowledgement', async () => {
  reserveRequest.mockResolvedValueOnce({ allowed: false, retryAfterSeconds: 15 });
  const limited = await handlers.GET(request());
  expect(limited.status).toBe(429);
  expect(limited.headers.get('Retry-After')).toBe('15');
  expect(sync).not.toHaveBeenCalled();
  sync.mockRejectedValueOnce(new Error('offline'));
  expect((await handlers.POST(request('POST', { changes: [record] }))).status).toBe(503);
});

it('distinguishes no gym filter, confirmed empty inventory, and exact equipment sets', async () => {
  const unrestricted = await (await handlers.exercises(request())).json();
  expect(unrestricted.exercises.map((item: { id: string }) => item.id)).toEqual(
    EXERCISE_CATALOG.map((item) => item.id),
  );
  const empty = await (await handlers.exercises(request('GET', undefined, '?equipment='))).json();
  expect(empty.exercises).toEqual([]);
  const filtered = await (
    await handlers.exercises(request('GET', undefined, '?equipment=dumbbells'))
  ).json();
  expect(filtered.exercises.length).toBeGreaterThan(0);
  expect(
    filtered.exercises.every((item: { requires: string[] }) =>
      item.requires.every((value) => value === 'dumbbells'),
    ),
  ).toBe(true);
  expect((await handlers.exercises(request('GET', undefined, '?equipment=unknown'))).status).toBe(
    400,
  );
  const all = CATALOG_EQUIPMENT.map((item) => 'equipment=' + item).join('&');
  expect(
    (await (await handlers.exercises(request('GET', undefined, '?' + all))).json()).exercises,
  ).toHaveLength(EXERCISE_CATALOG.length);
});
