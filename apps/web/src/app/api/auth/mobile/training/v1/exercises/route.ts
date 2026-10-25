import { NextRequest, NextResponse } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import {
  CATALOG_EQUIPMENT,
  queryExerciseLibrary,
  type CatalogEquipment,
} from '@/lib/training/catalog';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  const json = (body: unknown, status = 200) =>
    NextResponse.json(body, {
      status,
      headers: { 'Cache-Control': 'no-store' },
    });
  if (!bearer || !(await fetchUserInfo(bearer))) return json({ error: 'unauthorized' }, 401);
  const value = request.nextUrl.searchParams.get('equipment');
  const items = value ? value.split(',') : [];
  if (items.some((item) => !(CATALOG_EQUIPMENT as readonly string[]).includes(item))) {
    return json({ error: 'invalid_equipment' }, 400);
  }
  // Omitted = unrestricted; present but empty = user-confirmed empty inventory.
  const equipment = value === null ? null : new Set(items as CatalogEquipment[]);
  return json({ exercises: queryExerciseLibrary(equipment) });
}
