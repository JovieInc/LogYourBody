/** @jest-environment node */
import { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { EXERCISE_CATALOG } from '@/lib/training/catalog';
import { GET } from './route';
jest.mock('@/lib/auth/jovie-oauth', () => ({ fetchUserInfo: jest.fn() }));

function request(query = '') {
  return new NextRequest(`http://localhost/api/auth/mobile/training/v1/exercises${query}`, {
    headers: { authorization: 'Bearer synthetic' },
  });
}
describe('active gym exercise library filter', () => {
  beforeEach(() => jest.mocked(fetchUserInfo).mockResolvedValue({ sub: 'owner-a' }));
  it('allows the whole library with no gym and nothing with an explicit empty inventory', async () => {
    expect((await (await GET(request())).json()).exercises).toHaveLength(EXERCISE_CATALOG.length);
    expect((await (await GET(request('?equipment='))).json()).exercises).toEqual([]);
  });
  it('filters by all required items and changes with manual gym selection input', async () => {
    const dumbbells = (await (await GET(request('?equipment=dumbbells'))).json()).exercises;
    expect(dumbbells.length).toBeGreaterThan(0);
    expect(
      dumbbells.every((item: { requires: string[] }) =>
        item.requires.every((need) => need === 'dumbbells'),
      ),
    ).toBe(true);
    const smith = (await (await GET(request('?equipment=smith'))).json()).exercises;
    expect(smith).not.toEqual(dumbbells);
  });
  it('rejects unknown equipment and unauthenticated queries', async () => {
    expect((await GET(request('?equipment=inferred'))).status).toBe(400);
    jest.mocked(fetchUserInfo).mockResolvedValue(null);
    expect((await GET(request())).status).toBe(401);
  });
});
