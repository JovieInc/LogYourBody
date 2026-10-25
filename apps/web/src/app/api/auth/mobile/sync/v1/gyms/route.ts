import type { NextRequest } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonGymRegistry } from '@/lib/neon/gym-registry-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { createGymRegistryHandlers } from './route-handlers';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const handlers = createGymRegistryHandlers({
  authenticate: (request: NextRequest) => {
    const bearer = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
    return bearer ? fetchUserInfo(bearer) : Promise.resolve(null);
  },
  registry: neonGymRegistry,
  accounts: neonNativeProductRecords.accountMutations!,
});
export const GET = handlers.GET;
export const POST = handlers.POST;
export const DELETE = handlers.DELETE;
