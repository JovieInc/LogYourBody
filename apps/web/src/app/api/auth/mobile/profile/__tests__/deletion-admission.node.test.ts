/** @jest-environment node */
import { NextRequest } from 'next/server';
import { DELETE as mobileDelete } from '../route';
import { DELETE as webDelete } from '@/app/api/auth/delete-account/route';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { deleteOwnedProgressPhotos } from '@/lib/cloudflare/r2-progress-photo-store';
import {
  NativeAccountAdmissionError,
  type NativeAccountAdmission,
} from '@/lib/ports/native-account-admission';
jest.mock('@/lib/auth/jovie-oauth', () => ({ fetchUserInfo: async () => ({ sub: 'owner' }) }));
jest.mock('@/lib/ports/server-auth-runtime', () => ({
  getServerAuthSession: async () => ({ userId: 'owner' }),
}));
jest.mock('@/lib/neon/user-directory-adapter', () => ({
  neonUserDirectory: { captureAccountAdmission: jest.fn(), deleteUser: jest.fn() },
}));
jest.mock('@/lib/cloudflare/r2-progress-photo-store', () => ({
  deleteOwnedProgressPhotos: jest.fn(),
}));
const old = { subject: 'owner', ownerId: '11111111-1111-4111-8111-111111111111' };
const newer = { ...old, ownerId: '22222222-2222-4222-8222-222222222222' };
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
const req = () =>
  new NextRequest('http://localhost/api/auth/mobile/profile', {
    method: 'DELETE',
    headers: { authorization: 'Bearer synthetic' },
  });
beforeEach(() => jest.resetAllMocks());
it('mobile deletion retains the captured owner across external cleanup', async () => {
  let current: NativeAccountAdmission | null = old;
  const entered = deferred<void>();
  const release = deferred<void>();
  jest.mocked(neonUserDirectory.captureAccountAdmission).mockResolvedValue(old);
  jest.mocked(deleteOwnedProgressPhotos).mockImplementation(async () => {
    entered.resolve();
    await release.promise;
  });
  jest.mocked(neonUserDirectory.deleteUser).mockImplementation(async (a) => {
    if (typeof a === 'object' && a.ownerId !== current?.ownerId)
      throw new NativeAccountAdmissionError('account_changed');
    current = null;
  });
  const pending = mobileDelete(req());
  await entered.promise;
  current = newer;
  release.resolve();
  expect((await pending).status).toBe(409);
  expect(current).toEqual(newer);
  expect(neonUserDirectory.captureAccountAdmission).toHaveBeenCalledTimes(1);
});
it('web deletion carries its first capture into the final SQL admission', async () => {
  let current: NativeAccountAdmission | null = old;
  const entered = deferred<void>();
  const release = deferred<NativeAccountAdmission>();
  jest.mocked(neonUserDirectory.captureAccountAdmission).mockImplementation(() => {
    entered.resolve();
    return release.promise;
  });
  jest.mocked(neonUserDirectory.deleteUser).mockImplementation(async (a) => {
    if (typeof a === 'object' && a.ownerId !== current?.ownerId)
      throw new NativeAccountAdmissionError('account_changed');
    current = null;
  });
  const pending = webDelete();
  await entered.promise;
  current = newer;
  release.resolve(old);
  expect((await pending).status).toBe(409);
  expect(current).toEqual(newer);
  expect(deleteOwnedProgressPhotos).not.toHaveBeenCalled();
});
it('an already absent account succeeds without remote or SQL cleanup', async () => {
  jest.mocked(neonUserDirectory.captureAccountAdmission).mockResolvedValue(null);
  expect((await mobileDelete(req())).status).toBe(204);
  expect((await webDelete()).status).toBe(200);
  expect(deleteOwnedProgressPhotos).not.toHaveBeenCalled();
  expect(neonUserDirectory.deleteUser).not.toHaveBeenCalled();
});
