import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { VoiceProvider } from '@/lib/voice/provider';
import { parseVoiceIntent, type VoiceWeightUnit } from '@/lib/voice/intent-parser';

const VOICE_API_VERSION = 1;
const SpeakRequestSchema = z
  .object({
    text: z.string().trim().min(1).max(2_000),
    voiceId: z.string().trim().min(1).max(128).optional(),
  })
  .strict();

const IntentRequestSchema = z
  .object({
    transcript: z.string().trim().min(1).max(1_000),
    weightUnit: z.enum(['kg', 'lbs']).optional(),
    session: z
      .object({
        id: z.string().uuid(),
        exercises: z
          .array(
            z
              .object({
                id: z.string().trim().min(1).max(64),
                name: z.string().trim().min(1).max(120),
              })
              .strict(),
          )
          .max(32),
      })
      .strict()
      .optional(),
  })
  .strict();

type VoiceRouteDependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  enabled: () => boolean;
  provider: () => VoiceProvider | null;
  voiceId: () => string;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  createRequestId: () => string;
};

function jsonError(code: string, status: number, retryAfterSeconds?: number) {
  return NextResponse.json(
    { version: VOICE_API_VERSION, error: code },
    {
      status,
      headers: {
        'Cache-Control': 'no-store',
        ...(retryAfterSeconds ? { 'Retry-After': String(retryAfterSeconds) } : {}),
      },
    },
  );
}

function rateLimited(result: Extract<ChatRateLimitResult, { allowed: false }>) {
  return jsonError('rate_limited', 429, result.retryAfterSeconds);
}

export function createVoiceRouteHandlers(dependencies: VoiceRouteDependencies) {
  async function authorize(request: NextRequest) {
    const user = await dependencies.authenticate(request);
    if (!user) return { error: jsonError('unauthorized', 401) } as const;
    if (!dependencies.enabled()) return { error: jsonError('not_found', 404) } as const;
    const limit = await dependencies.reserveRequest(user.sub);
    if (!limit.allowed) return { error: rateLimited(limit) } as const;
    return { user } as const;
  }

  return {
    async speak(request: NextRequest) {
      const authorized = await authorize(request);
      if ('error' in authorized) return authorized.error;
      const parsed = SpeakRequestSchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return jsonError('invalid_request', 400);

      const provider = dependencies.provider();
      if (!provider) return jsonError('provider_unavailable', 503);
      const requestId = dependencies.createRequestId();
      try {
        const audio = await provider.tts(
          parsed.data.text,
          parsed.data.voiceId ?? dependencies.voiceId(),
          {
            signal: request.signal,
          },
        );
        return new Response(audio, {
          status: 200,
          headers: {
            'Cache-Control': 'no-store',
            'Content-Type': 'audio/mpeg',
            'X-Content-Type-Options': 'nosniff',
            'X-Request-Id': requestId,
            Vary: 'Authorization',
          },
        });
      } catch {
        return jsonError('voice_unavailable', 503);
      }
    },

    async intent(request: NextRequest) {
      const authorized = await authorize(request);
      if ('error' in authorized) return authorized.error;
      const parsed = IntentRequestSchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return jsonError('invalid_request', 400);

      const input = parsed.data;
      const weightUnit: VoiceWeightUnit | undefined = input.weightUnit;
      const result = parseVoiceIntent(input.transcript, {
        sessionId: input.session?.id,
        exercises: input.session?.exercises,
        weightUnit,
      });
      return NextResponse.json(
        { version: VOICE_API_VERSION, ...result },
        { headers: { 'Cache-Control': 'no-store' } },
      );
    },
  };
}
