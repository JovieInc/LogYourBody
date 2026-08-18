import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import {
  PROGRESS_PHOTO_MAX_BYTES,
  createProgressPhotoUploadTicket,
  isProgressPhotoContentType,
  readR2PhotoStoreConfig,
} from '@/lib/cloudflare/r2-progress-photo-store';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const PhotoUploadRequestSchema = z
  .object({
    metricsId: z.string().regex(/^[A-Za-z0-9_-]{8,80}$/),
    contentType: z
      .string()
      .optional()
      .transform((value) => value ?? 'image/jpeg'),
    byteSize: z.number().int().min(1).max(PROGRESS_PHOTO_MAX_BYTES).optional(),
  })
  .strict();

const unavailableMessage =
  'Progress photo cloud storage is not available. Photos stay on this device until Cloudflare R2 is configured on the first-party API.';

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

function noStoreJson(body: unknown, status: number) {
  return NextResponse.json(body, {
    status,
    headers: { 'Cache-Control': 'no-store' },
  });
}

export async function POST(request: NextRequest) {
  const identity = await authenticate(request);
  if (!identity) {
    return noStoreJson({ error: 'unauthorized' }, 401);
  }

  const config = readR2PhotoStoreConfig();
  if (!config) {
    return noStoreJson(
      {
        error: 'photo_store_unavailable',
        message: unavailableMessage,
      },
      503,
    );
  }

  const parsed = PhotoUploadRequestSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return noStoreJson({ error: 'invalid_photo_upload' }, 400);
  }

  const contentType = parsed.data.contentType;
  if (!isProgressPhotoContentType(contentType)) {
    return noStoreJson({ error: 'invalid_photo_upload' }, 400);
  }

  try {
    const ticket = createProgressPhotoUploadTicket({
      config,
      userId: identity.sub,
      metricsId: parsed.data.metricsId,
      contentType,
    });
    return noStoreJson(ticket, 200);
  } catch (error) {
    if (error instanceof Error && error.message === 'invalid_metrics_id') {
      return noStoreJson({ error: 'invalid_photo_upload' }, 400);
    }
    console.error('Progress photo upload ticket failed', error);
    return noStoreJson({ error: 'photo_store_unavailable', message: unavailableMessage }, 503);
  }
}
