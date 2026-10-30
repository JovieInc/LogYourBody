import { NextResponse } from 'next/server';
import { z } from 'zod';
import { HEALTH_VAULT_WIDGET_DOMAIN } from './constants';
import type { HealthVaultService, ShareField } from './types';
import { HEALTH_VAULT_SHARE_FIELDS } from './types';

const viewBody = z.object({ handle: z.string().trim().min(8).max(200) }).strict();
const consentBody = z
  .object({
    confirmToken: z.string().trim().min(8).max(200),
    fields: z.array(z.enum(HEALTH_VAULT_SHARE_FIELDS)).min(1).max(HEALTH_VAULT_SHARE_FIELDS.length),
  })
  .strict();

const MEDIA_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

export type HealthVaultMediaReader = {
  read(token: string): Promise<{ contentType: string; bytes: Uint8Array } | null>;
};

function corsOrigin(request: Request, apiOrigin: string): string | null {
  const origin = request.headers.get('origin');
  if (!origin) return null;
  if (origin === HEALTH_VAULT_WIDGET_DOMAIN || origin === apiOrigin) return origin;
  if (/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return origin;
  return null;
}

function headers(request: Request, apiOrigin: string, extra: Record<string, string> = {}) {
  const origin = corsOrigin(request, apiOrigin);
  return {
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    vary: 'origin',
    ...(origin ? { 'access-control-allow-origin': origin } : {}),
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type',
    ...extra,
  };
}

async function readJson(request: Request): Promise<unknown> {
  const text = await request.text();
  if (text.length > 4_000) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

export function createHealthVaultHttpHandlers(input: {
  enabled: () => boolean;
  service: HealthVaultService;
  media: HealthVaultMediaReader;
  apiOrigin: (request: Request) => string;
}) {
  const notFound = (request: Request, apiOrigin: string) =>
    new NextResponse(null, { status: 404, headers: headers(request, apiOrigin) });

  return {
    options(request: Request) {
      if (!input.enabled()) return notFound(request, input.apiOrigin(request));
      return new NextResponse(null, {
        status: 204,
        headers: headers(request, input.apiOrigin(request)),
      });
    },

    async view(request: Request) {
      const apiOrigin = input.apiOrigin(request);
      if (!input.enabled()) return notFound(request, apiOrigin);
      const parsed = viewBody.safeParse(await readJson(request));
      if (!parsed.success) {
        return NextResponse.json(
          { error: 'invalid_request' },
          { status: 400, headers: headers(request, apiOrigin) },
        );
      }
      const redeemed = await input.service.redeem(parsed.data.handle, apiOrigin);
      if (!redeemed.ok) return notFound(request, apiOrigin);
      return NextResponse.json(redeemed.view, { headers: headers(request, apiOrigin) });
    },

    async consents(request: Request) {
      const apiOrigin = input.apiOrigin(request);
      if (!input.enabled()) return notFound(request, apiOrigin);
      const parsed = consentBody.safeParse(await readJson(request));
      if (!parsed.success) {
        return NextResponse.json(
          { error: 'invalid_request' },
          { status: 400, headers: headers(request, apiOrigin) },
        );
      }
      const confirmed = await input.service.confirm({
        confirmToken: parsed.data.confirmToken,
        fields: parsed.data.fields as ShareField[],
      });
      if (!confirmed.ok) return notFound(request, apiOrigin);
      return NextResponse.json(
        { consentId: confirmed.consentId },
        { headers: headers(request, apiOrigin) },
      );
    },

    async media(request: Request) {
      const apiOrigin = input.apiOrigin(request);
      if (!input.enabled()) return notFound(request, apiOrigin);
      const token = new URL(request.url).searchParams.get('token') ?? '';
      if (token.length < 8 || token.length > 200) return notFound(request, apiOrigin);
      const media = await input.media.read(token);
      if (!media || !MEDIA_TYPES.has(media.contentType)) return notFound(request, apiOrigin);
      return new NextResponse(Buffer.from(media.bytes), {
        headers: headers(request, apiOrigin, {
          'content-type': media.contentType,
          'content-disposition': 'inline',
        }),
      });
    },
  };
}
