import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';
import { buildChatModelMessages } from '@/lib/chat/context';
import {
  CHAT_PROTOCOL_VERSION,
  type ChatConversationPort,
  type StoredChatMessage,
} from '@/lib/ports/chat-conversations';
import type { ChatModelMessage, ChatModelPort } from '@/lib/ports/chat-model';
import type { BodyMetricsPort } from '@/lib/ports/body-metrics';
import type { UserDirectoryPort } from '@/lib/ports/user-directory';

const ChatRequestSchema = z
  .object({
    protocolVersion: z.literal(CHAT_PROTOCOL_VERSION),
    conversationId: z.string().uuid(),
    clientMessageId: z.string().uuid(),
    message: z.string().trim().min(1).max(2_000),
  })
  .strict();

type ChatRouteDependencies = {
  authenticate: (request: NextRequest) => Promise<JovieUserInfo | null>;
  conversations: ChatConversationPort;
  bodyMetrics: BodyMetricsPort;
  users: UserDirectoryPort;
  createModel: () => ChatModelPort;
  modelName: string;
  createLeaseToken: () => string;
};

const encoder = new TextEncoder();

function event(name: string, payload: Record<string, unknown>): Uint8Array {
  return encoder.encode(`event: ${name}\ndata: ${JSON.stringify(payload)}\n\n`);
}

function streamHeaders() {
  return {
    'Cache-Control': 'no-cache, no-store, no-transform',
    'Content-Type': 'text/event-stream; charset=utf-8',
    'X-Accel-Buffering': 'no',
  };
}

function jsonError(code: string, status: number, headers?: HeadersInit) {
  return NextResponse.json(
    { version: CHAT_PROTOCOL_VERSION, error: code },
    { status, headers: { 'Cache-Control': 'no-store', ...headers } },
  );
}

function replayResponse(input: {
  conversationId: string;
  clientMessageId: string;
  message: StoredChatMessage;
}) {
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(
        event('meta', {
          version: CHAT_PROTOCOL_VERSION,
          conversationId: input.conversationId,
          clientMessageId: input.clientMessageId,
          replayed: true,
        }),
      );
      controller.enqueue(
        event('delta', {
          version: CHAT_PROTOCOL_VERSION,
          text: input.message.content,
        }),
      );
      controller.enqueue(
        event('done', {
          version: CHAT_PROTOCOL_VERSION,
          messageId: input.message.id,
          createdAt: input.message.createdAt,
          replayed: true,
        }),
      );
      controller.close();
    },
  });
  return new Response(body, { status: 200, headers: streamHeaders() });
}

export function createChatRouteHandlers(dependencies: ChatRouteDependencies) {
  async function authorized(request: NextRequest) {
    return dependencies.authenticate(request);
  }

  return {
    async GET(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return jsonError('unauthorized', 401);

      await dependencies.conversations.purgeExpired();
      const conversation = await dependencies.conversations.getLatest(identity.sub);
      return NextResponse.json(
        { version: CHAT_PROTOCOL_VERSION, conversation },
        { headers: { 'Cache-Control': 'no-store' } },
      );
    },

    async DELETE(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return jsonError('unauthorized', 401);

      const conversationId = request.nextUrl.searchParams.get('conversationId');
      if (!conversationId || !z.string().uuid().safeParse(conversationId).success) {
        return jsonError('invalid_conversation_id', 400);
      }

      await dependencies.conversations.purgeExpired();
      const deleted = await dependencies.conversations.deleteConversation(
        identity.sub,
        conversationId,
      );
      if (!deleted) return jsonError('conversation_not_found', 404);
      return new NextResponse(null, { status: 204, headers: { 'Cache-Control': 'no-store' } });
    },

    async POST(request: NextRequest) {
      const identity = await authorized(request);
      if (!identity) return jsonError('unauthorized', 401);

      const parsed = ChatRequestSchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return jsonError('invalid_request', 400);
      const input = parsed.data;

      const rateLimit = await dependencies.conversations.reserveRequest(identity.sub);
      if (!rateLimit.allowed) {
        return jsonError('rate_limited', 429, {
          'Retry-After': String(rateLimit.retryAfterSeconds),
        });
      }

      await dependencies.conversations.purgeExpired();
      const leaseToken = dependencies.createLeaseToken();
      const turn = await dependencies.conversations.beginTurn({
        subject: identity.sub,
        conversationId: input.conversationId,
        clientMessageId: input.clientMessageId,
        content: input.message,
        title: input.message.slice(0, 120),
        leaseToken,
      });

      if (turn.kind === 'replay') {
        return replayResponse({
          conversationId: turn.conversationId,
          clientMessageId: input.clientMessageId,
          message: turn.assistantMessage,
        });
      }
      if (turn.kind === 'in_progress') {
        return jsonError('turn_in_progress', 409, { 'Retry-After': '2' });
      }
      if (turn.kind === 'idempotency_conflict') {
        return jsonError('idempotency_conflict', 409);
      }
      if (turn.kind === 'not_found') {
        return jsonError('conversation_not_found', 404);
      }

      let model: ChatModelPort;
      let modelMessages: ChatModelMessage[];
      try {
        const [user, metrics] = await Promise.all([
          dependencies.users.getUser(identity.sub),
          dependencies.bodyMetrics.list(identity.sub, 30),
        ]);
        modelMessages = buildChatModelMessages({
          user,
          metrics,
          conversationMessages: turn.conversation.messages,
        });
        model = dependencies.createModel();
      } catch {
        await dependencies.conversations.failTurn({
          subject: identity.sub,
          turnId: turn.turnId,
          leaseToken,
          status: 'failed',
          failureCode: 'context_unavailable',
        });
        return jsonError('chat_unavailable', 503, { 'Retry-After': '5' });
      }

      const abortController = new AbortController();
      const abortFromRequest = () => abortController.abort();
      request.signal.addEventListener('abort', abortFromRequest, { once: true });
      let finalized = false;

      const body = new ReadableStream<Uint8Array>({
        async start(controller) {
          controller.enqueue(
            event('meta', {
              version: CHAT_PROTOCOL_VERSION,
              conversationId: input.conversationId,
              clientMessageId: input.clientMessageId,
              replayed: false,
            }),
          );

          let content = '';
          let inputTokens: number | null = null;
          let outputTokens: number | null = null;

          try {
            for await (const modelEvent of model.streamText({
              messages: modelMessages,
              maxOutputTokens: 600,
              signal: abortController.signal,
            })) {
              if (modelEvent.type === 'text_delta') {
                content += modelEvent.text;
                if (content.length > 12_000) throw new Error('CHAT_RESPONSE_TOO_LONG');
                controller.enqueue(
                  event('delta', {
                    version: CHAT_PROTOCOL_VERSION,
                    text: modelEvent.text,
                  }),
                );
              } else {
                inputTokens = modelEvent.inputTokens;
                outputTokens = modelEvent.outputTokens;
              }
            }

            if (!content.trim()) throw new Error('CHAT_EMPTY_RESPONSE');
            const stored = await dependencies.conversations.completeTurn({
              subject: identity.sub,
              turnId: turn.turnId,
              leaseToken,
              content,
              model: dependencies.modelName,
              inputTokens,
              outputTokens,
            });
            finalized = true;
            controller.enqueue(
              event('done', {
                version: CHAT_PROTOCOL_VERSION,
                messageId: stored.id,
                createdAt: stored.createdAt,
                replayed: false,
              }),
            );
          } catch {
            const cancelled = abortController.signal.aborted;
            await dependencies.conversations.failTurn({
              subject: identity.sub,
              turnId: turn.turnId,
              leaseToken,
              status: cancelled ? 'cancelled' : 'failed',
              failureCode: cancelled ? 'client_cancelled' : 'provider_error',
            });
            if (!cancelled) {
              controller.enqueue(
                event('error', {
                  version: CHAT_PROTOCOL_VERSION,
                  code: 'provider_error',
                  message: 'The answer could not be completed.',
                  retryable: true,
                }),
              );
            }
          } finally {
            request.signal.removeEventListener('abort', abortFromRequest);
            controller.close();
          }
        },
        async cancel() {
          abortController.abort();
          if (!finalized) {
            await dependencies.conversations.failTurn({
              subject: identity.sub,
              turnId: turn.turnId,
              leaseToken,
              status: 'cancelled',
              failureCode: 'client_cancelled',
            });
          }
        },
      });

      return new Response(body, { status: 200, headers: streamHeaders() });
    },
  };
}
