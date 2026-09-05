/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createChatRouteHandlers } from '../route-handlers';
import type {
  BeginChatTurnInput,
  ChatConversationPort,
  ChatRateLimitResult,
  StoredChatConversation,
  StoredChatMessage,
} from '@/lib/ports/chat-conversations';
import type {
  ChatModelMessage,
  ChatModelPort,
  ChatModelStreamEvent,
  ChatModelStreamRequest,
} from '@/lib/ports/chat-model';
import type { BodyMetricsPort, ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { ProductUserRecord, UserDirectoryPort } from '@/lib/ports/user-directory';

const now = '2026-08-02T22:00:00.000Z';
const conversationId = '11111111-1111-4111-8111-111111111111';
const clientMessageId = '22222222-2222-4222-8222-222222222222';

type MemoryTurn = {
  id: string;
  owner: string;
  content: string;
  status: 'pending' | 'completed' | 'failed' | 'cancelled';
  leaseToken: string;
  userMessage: StoredChatMessage;
  assistantMessage?: StoredChatMessage;
};

class MemoryConversationStore implements ChatConversationPort {
  conversations = new Map<string, { owner: string; conversation: StoredChatConversation }>();
  turns = new Map<string, MemoryTurn>();
  reserveCalls = 0;
  rateLimit: ChatRateLimitResult = {
    allowed: true,
    remainingInWindow: 11,
    remainingToday: 99,
  };

  async purgeExpired() {
    return 0;
  }

  async getLatest(subject: string) {
    const values = [...this.conversations.values()].filter(({ owner }) => owner === subject);
    return values.at(-1)?.conversation ?? null;
  }

  async beginTurn(input: BeginChatTurnInput) {
    const existingConversation = this.conversations.get(input.conversationId);
    if (existingConversation && existingConversation.owner !== input.subject) {
      return { kind: 'not_found' as const };
    }

    if (!existingConversation) {
      this.conversations.set(input.conversationId, {
        owner: input.subject,
        conversation: {
          id: input.conversationId,
          title: input.title,
          createdAt: now,
          updatedAt: now,
          expiresAt: '2026-09-01T22:00:00.000Z',
          messages: [],
        },
      });
    }

    const key = `${input.conversationId}:${input.clientMessageId}`;
    const existingTurn = this.turns.get(key);
    if (existingTurn) {
      if (existingTurn.content !== input.content) return { kind: 'idempotency_conflict' as const };
      if (existingTurn.status === 'completed' && existingTurn.assistantMessage) {
        return {
          kind: 'replay' as const,
          conversationId: input.conversationId,
          assistantMessage: existingTurn.assistantMessage,
        };
      }
      if (existingTurn.status === 'pending') return { kind: 'in_progress' as const };
      existingTurn.status = 'pending';
      existingTurn.leaseToken = input.leaseToken;
      return {
        kind: 'claimed' as const,
        conversation: this.conversations.get(input.conversationId)!.conversation,
        turnId: existingTurn.id,
        leaseToken: input.leaseToken,
      };
    }

    const userMessage: StoredChatMessage = {
      id: `user-${this.turns.size + 1}`,
      role: 'user',
      content: input.content,
      clientMessageId: input.clientMessageId,
      createdAt: now,
    };
    const turn: MemoryTurn = {
      id: `turn-${this.turns.size + 1}`,
      owner: input.subject,
      content: input.content,
      status: 'pending',
      leaseToken: input.leaseToken,
      userMessage,
    };
    this.turns.set(key, turn);
    const conversation = this.conversations.get(input.conversationId)!.conversation;
    conversation.messages.push(userMessage);
    return {
      kind: 'claimed' as const,
      conversation,
      turnId: turn.id,
      leaseToken: input.leaseToken,
    };
  }

  async reserveRequest() {
    this.reserveCalls += 1;
    return this.rateLimit;
  }

  async completeTurn(input: {
    subject: string;
    turnId: string;
    leaseToken: string;
    content: string;
  }) {
    const entry = [...this.turns.entries()].find(([, turn]) => turn.id === input.turnId);
    if (!entry) throw new Error('missing turn');
    const [key, turn] = entry;
    if (turn.owner !== input.subject || turn.leaseToken !== input.leaseToken) {
      throw new Error('wrong owner');
    }
    const message: StoredChatMessage = {
      id: `assistant-${turn.id}`,
      role: 'assistant',
      content: input.content,
      clientMessageId: null,
      createdAt: now,
    };
    turn.status = 'completed';
    turn.assistantMessage = message;
    const conversation = this.conversations.get(key.split(':')[0])!.conversation;
    if (!conversation.messages.some(({ id }) => id === message.id))
      conversation.messages.push(message);
    return message;
  }

  async failTurn(input: {
    subject: string;
    turnId: string;
    leaseToken: string;
    status: 'failed' | 'cancelled';
  }) {
    const turn = [...this.turns.values()].find(({ id }) => id === input.turnId);
    if (turn && turn.owner === input.subject && turn.leaseToken === input.leaseToken) {
      turn.status = input.status;
    }
  }

  async deleteConversation(subject: string, id: string) {
    const value = this.conversations.get(id);
    if (!value || value.owner !== subject) return false;
    this.conversations.delete(id);
    for (const key of this.turns.keys()) {
      if (key.startsWith(`${id}:`)) this.turns.delete(key);
    }
    return true;
  }
}

class FixtureModel implements ChatModelPort {
  calls: ChatModelStreamRequest[] = [];
  chunks = ['Your ', 'trend is stable.'];
  shouldFail = false;
  waitForCancellation = false;

  async *streamText(request: ChatModelStreamRequest): AsyncIterable<ChatModelStreamEvent> {
    this.calls.push(request);
    if (this.shouldFail) throw new Error('fixture provider failure');
    for (const text of this.chunks) yield { type: 'text_delta', text };
    if (this.waitForCancellation) {
      await new Promise<void>((_resolve, reject) => {
        request.signal.addEventListener(
          'abort',
          () => reject(new DOMException('Aborted', 'AbortError')),
          { once: true },
        );
      });
    }
    yield { type: 'usage', inputTokens: 30, outputTokens: 8 };
  }
}

function user(subject: string): ProductUserRecord {
  return {
    subject,
    phoneNumber: null,
    email: null,
    displayName: null,
    avatarUrl: null,
    profileData: { height: 180, height_unit: 'cm' },
    onboardingCompletedAt: now as never,
    legalAcceptedAt: now as never,
    termsVersion: '2026-07-14',
    privacyVersion: '2026-07-14',
  };
}

function metric(subject: string): ProductBodyMetric {
  return {
    id: 'metric-1',
    user_subject: subject,
    date: '2026-08-01',
    weight: 80,
    weight_unit: 'kg',
    body_fat_percentage: 18,
    body_fat_method: 'dexa',
    muscle_mass: null,
    waist: null,
    neck: null,
    hip: null,
    notes: 'must not enter model context',
    photo_url: 'https://example.com/private-photo.jpg',
    data_source: 'bodyspec_dexa',
    source_metadata: { private: true },
    created_at: now,
    updated_at: now,
  };
}

function makeHarness() {
  const store = new MemoryConversationStore();
  const model = new FixtureModel();
  const getUser = jest.fn(async (subject: string) => user(subject));
  const listMetrics = jest.fn(async (subject: string) => [metric(subject)]);
  let lease = 0;
  const reportStreamOutcome = jest.fn();
  const handlers = createChatRouteHandlers({
    authenticate: async (request) => {
      const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
      if (!token || token === 'expired') return null;
      return { sub: token };
    },
    conversations: store,
    bodyMetrics: {
      list: listMetrics,
      upsert: jest.fn(),
    } as BodyMetricsPort,
    users: {
      recordSignIn: jest.fn(),
      getUser,
      updateProfile: jest.fn(),
      deleteUser: jest.fn(),
    } as UserDirectoryPort,
    createModel: () => model,
    reportStreamOutcome,
    modelName: 'fixture-model',
    createLeaseToken: () => `33333333-3333-4333-8333-${String(++lease).padStart(12, '0')}`,
  });
  return { handlers, store, model, getUser, listMetrics, reportStreamOutcome };
}

function request(method: 'GET' | 'POST' | 'DELETE', token = 'user-a', body?: unknown, query = '') {
  return new NextRequest(`http://localhost/api/auth/mobile/chat/v1${query}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

function chatBody(message = 'How am I doing?') {
  return { protocolVersion: 1, conversationId, clientMessageId, message };
}

describe('/api/auth/mobile/chat/v1', () => {
  it('rejects missing and expired bearer tokens before context access', async () => {
    const { handlers, getUser, listMetrics } = makeHarness();
    const missing = new NextRequest('http://localhost/api/auth/mobile/chat/v1', { method: 'GET' });
    expect((await handlers.GET(missing)).status).toBe(401);
    expect((await handlers.POST(request('POST', 'expired', chatBody()))).status).toBe(401);
    expect(getUser).not.toHaveBeenCalled();
    expect(listMetrics).not.toHaveBeenCalled();
  });

  it('streams, persists, reloads, and scopes authorized body context', async () => {
    const { handlers, model, getUser, listMetrics } = makeHarness();
    const response = await handlers.POST(request('POST', 'user-a', chatBody()));
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/event-stream');
    const stream = await response.text();
    expect(stream).toContain('event: meta');
    expect(stream).toContain('Your ');
    expect(stream).toContain('trend is stable.');
    expect(stream).toContain('event: done');
    expect(getUser).toHaveBeenCalledWith('user-a');
    expect(listMetrics).toHaveBeenCalledWith('user-a', 30);

    const modelContext = model.calls[0].messages as ChatModelMessage[];
    expect(modelContext[0].content).toContain('"weight":80');
    expect(modelContext[0].content).not.toContain('must not enter model context');
    expect(modelContext[0].content).not.toContain('example.com');
    expect(modelContext[0].content).not.toContain('bodyspec_dexa');
    expect(modelContext[0].content).not.toContain('private');

    const reload = await handlers.GET(request('GET', 'user-a'));
    expect(reload.status).toBe(200);
    await expect(reload.json()).resolves.toMatchObject({
      version: 1,
      conversation: {
        id: conversationId,
        messages: [
          { role: 'user', content: 'How am I doing?' },
          { role: 'assistant', content: 'Your trend is stable.' },
        ],
      },
    });
  });

  it('isolates conversations across authenticated subjects', async () => {
    const { handlers } = makeHarness();
    await (await handlers.POST(request('POST', 'user-a', chatBody()))).text();

    const otherUserReload = await handlers.GET(request('GET', 'user-b'));
    await expect(otherUserReload.json()).resolves.toMatchObject({ conversation: null });
    expect(
      (
        await handlers.DELETE(
          request('DELETE', 'user-b', undefined, `?conversationId=${conversationId}`),
        )
      ).status,
    ).toBe(404);
    expect((await handlers.POST(request('POST', 'user-b', chatBody()))).status).toBe(404);
  });

  it('replays a completed idempotent turn without another model request', async () => {
    const { handlers, model, store } = makeHarness();
    await (await handlers.POST(request('POST', 'user-a', chatBody()))).text();
    const replay = await handlers.POST(request('POST', 'user-a', chatBody()));
    const replayText = await replay.text();

    expect(replay.status).toBe(200);
    expect(replayText).toContain('"replayed":true');
    expect(model.calls).toHaveLength(1);
    expect(store.reserveCalls).toBe(2);
  });

  it('rejects a concurrent replay while the original turn owns the lease', async () => {
    const { handlers, model, store } = makeHarness();
    model.waitForCancellation = true;

    const original = await handlers.POST(request('POST', 'user-a', chatBody()));
    const duplicate = await handlers.POST(request('POST', 'user-a', chatBody()));

    expect(duplicate.status).toBe(409);
    expect(duplicate.headers.get('retry-after')).toBe('2');
    await expect(duplicate.json()).resolves.toMatchObject({ error: 'turn_in_progress' });
    expect(model.calls).toHaveLength(1);
    expect(store.reserveCalls).toBe(2);

    const reader = original.body!.getReader();
    await reader.read();
    await reader.cancel();
  });

  it('rejects reuse of an idempotency key for different content', async () => {
    const { handlers } = makeHarness();
    await (await handlers.POST(request('POST', 'user-a', chatBody()))).text();
    const conflict = await handlers.POST(request('POST', 'user-a', chatBody('Different content')));
    expect(conflict.status).toBe(409);
    await expect(conflict.json()).resolves.toMatchObject({ error: 'idempotency_conflict' });
  });

  it('marks a disconnected stream as cancelled', async () => {
    const { handlers, model, store } = makeHarness();
    model.waitForCancellation = true;
    const response = await handlers.POST(request('POST', 'user-a', chatBody()));
    const reader = response.body!.getReader();
    await reader.read();
    await reader.cancel();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect([...store.turns.values()][0]?.status).toBe('cancelled');
  });

  it('surfaces provider failure and permits a same-key retry without duplicating the user message', async () => {
    const { handlers, model, store } = makeHarness();
    model.shouldFail = true;
    const failed = await handlers.POST(request('POST', 'user-a', chatBody()));
    expect(await failed.text()).toContain('event: error');
    expect([...store.turns.values()][0]?.status).toBe('failed');

    model.shouldFail = false;
    const retried = await handlers.POST(request('POST', 'user-a', chatBody()));
    expect(await retried.text()).toContain('event: done');
    const conversation = await store.getLatest('user-a');
    expect(conversation?.messages.filter(({ role }) => role === 'user')).toHaveLength(1);
    expect(conversation?.messages.filter(({ role }) => role === 'assistant')).toHaveLength(1);
  });

  it('delivers a terminal stream error even when failure persistence is unavailable', async () => {
    const { handlers, model, store, reportStreamOutcome } = makeHarness();
    model.shouldFail = true;
    jest.spyOn(store, 'failTurn').mockRejectedValue(new Error('synthetic persistence outage'));
    const response = await handlers.POST(request('POST', 'user-a', chatBody('Say hello.')));
    const stream = await response.text();
    expect(stream).toContain('event: meta');
    expect(stream).toContain('event: error');
    expect(stream).not.toContain('event: done');
    expect(stream).not.toContain('synthetic persistence outage');
    expect(reportStreamOutcome.mock.calls).toEqual([
      ['started'],
      ['provider_error'],
      ['failure_persistence_error'],
    ]);
  });

  it('distinguishes completion persistence failure from model failure without exposing content', async () => {
    const { handlers, store, reportStreamOutcome } = makeHarness();
    jest.spyOn(store, 'completeTurn').mockRejectedValue(new Error('private database detail'));
    const response = await handlers.POST(request('POST', 'user-a', chatBody('Say hello.')));
    const stream = await response.text();
    expect(stream).toContain('event: error');
    expect(stream).not.toContain('event: done');
    expect(stream).not.toContain('private database detail');
    expect(reportStreamOutcome.mock.calls).toEqual([['started'], ['completion_persistence_error']]);
    expect([...store.turns.values()][0]?.status).toBe('failed');
  });

  it('keeps the answer lifecycle intact when diagnostics throw', async () => {
    const { handlers, reportStreamOutcome } = makeHarness();
    reportStreamOutcome.mockImplementation(() => {
      throw new Error('diagnostic sink unavailable');
    });
    const response = await handlers.POST(request('POST', 'user-a', chatBody('Say hello.')));
    expect(await response.text()).toContain('event: done');
    expect(reportStreamOutcome.mock.calls).toEqual([['started'], ['completed']]);
  });

  it('reports an empty provider stream as failure rather than completed', async () => {
    const { handlers, model, reportStreamOutcome } = makeHarness();
    model.chunks = [];
    const response = await handlers.POST(request('POST', 'user-a', chatBody('Say hello.')));
    const stream = await response.text();
    expect(stream).toContain('event: error');
    expect(stream).not.toContain('event: done');
    expect(reportStreamOutcome.mock.calls).toEqual([['started'], ['provider_error']]);
  });

  it('enforces persisted request limits and permits owner deletion', async () => {
    const { handlers, store } = makeHarness();
    store.rateLimit = { allowed: false, retryAfterSeconds: 42 };
    const limited = await handlers.POST(request('POST', 'user-a', chatBody()));
    expect(limited.status).toBe(429);
    expect(limited.headers.get('retry-after')).toBe('42');
    expect(store.conversations.size).toBe(0);

    store.rateLimit = { allowed: true, remainingInWindow: 10, remainingToday: 98 };
    await (await handlers.POST(request('POST', 'user-a', chatBody()))).text();
    const deleted = await handlers.DELETE(
      request('DELETE', 'user-a', undefined, `?conversationId=${conversationId}`),
    );
    expect(deleted.status).toBe(204);
    await expect((await handlers.GET(request('GET', 'user-a'))).json()).resolves.toMatchObject({
      conversation: null,
    });
  });
});
