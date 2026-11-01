/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createChatRouteHandlers } from '../route-handlers';
import { COACH_PERSONA_GUARDRAILS_FLAG } from '@/lib/flags/coach-persona';
import { MemoryConversationStore } from '../../../../../../../../tests/fixtures/chat-conversations';
import type {
  ChatModelMessage,
  ChatModelPort,
  ChatModelStreamEvent,
  ChatModelStreamRequest,
} from '@/lib/ports/chat-model';
import type { BodyMetricsPort, ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { ProductUserRecord, UserDirectoryPort } from '@/lib/ports/user-directory';
import type { ControllerReceipt } from '@/lib/training/controller';
import type { NextWorkoutResult } from '@/lib/training/service';

const holdDecision: ControllerReceipt = {
  decision: { kind: 'hold', optionalBurdenReduction: false },
  actor: 'controller',
  rationale: 'Trajectory matches plan.',
  signalFreshness: { training: 'fresh', recovery: 'fresh', trajectory: 'missing' },
  evidenceIds: ['k:81c218db'],
  before: 'plan',
  after: 'Plan unchanged.',
  reviewPoint: 'Next scheduled session',
  nextAction: 'On track.',
};

const now = '2026-08-02T22:00:00.000Z';
const conversationId = '11111111-1111-4111-8111-111111111111';
const clientMessageId = '22222222-2222-4222-8222-222222222222';

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

function makeHarness(
  trainingOutput?: NextWorkoutResult,
  steering?: { content: string; proposalId?: string },
) {
  const store = new MemoryConversationStore();
  const model = new FixtureModel();
  const getUser = jest.fn(async (subject: string) => user(subject));
  const listMetrics = jest.fn(async (subject: string) => [metric(subject)]);
  let lease = 0;
  const reportStreamOutcome = jest.fn();
  const getTrainingOutput = jest.fn(async () => trainingOutput ?? null);
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
    getTrainingOutput,
    proposeTrainingSteering: async () => steering ?? null,
    modelName: 'fixture-model',
    createLeaseToken: () => `33333333-3333-4333-8333-${String(++lease).padStart(12, '0')}`,
  });
  return { handlers, store, model, getUser, listMetrics, reportStreamOutcome, getTrainingOutput };
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
  afterEach(() => {
    delete process.env.LYB_COACH_PERSONA_GUARDRAILS_V1;
  });

  it('chat and voice persist a reviewable steering proposal without a model-generated change claim', async () => {
    const h = makeHarness(undefined, {
      content: 'Draft ready. Keep the exact cable curl variant. Your saved plan has not changed.',
      proposalId: 'proposal-id',
    });
    const response = await h.handlers.POST(
      request('POST', 'user-a', { ...chatBody('keep cable curls'), voiceMode: true }),
    );
    const stream = await response.text();
    expect(stream).toContain('event: plan_proposal');
    expect(stream).toContain('"applied":false');
    expect(stream).toContain('Your saved plan has not changed.');
    expect(h.model.calls).toHaveLength(0);
    expect(h.getTrainingOutput).not.toHaveBeenCalled();
  });

  it('rejects missing and expired bearer tokens before context access', async () => {
    const { handlers, getUser, listMetrics } = makeHarness();
    const missing = new NextRequest('http://localhost/api/auth/mobile/chat/v1', { method: 'GET' });
    expect((await handlers.GET(missing)).status).toBe(401);
    expect((await handlers.POST(request('POST', 'expired', chatBody()))).status).toBe(401);
    expect(getUser).not.toHaveBeenCalled();
    expect(listMetrics).not.toHaveBeenCalled();
  });

  it('streams, persists, reloads, and scopes authorized body context', async () => {
    const previous = process.env.LYB_COACH_PERSONA_GUARDRAILS_V1;
    process.env.LYB_COACH_PERSONA_GUARDRAILS_V1 = '1';
    const { handlers, model, getUser, listMetrics } = makeHarness();
    const response = await handlers.POST(
      request('POST', 'user-a', { ...chatBody(), voiceMode: true }),
    );
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
    expect(modelContext[0].content).toContain('Voice reply mode is active');
    expect(modelContext[0].content).toContain('"weight":80');
    expect(modelContext[0].content).not.toContain('must not enter model context');
    expect(modelContext[0].content).not.toContain('example.com');
    expect(modelContext[0].content).not.toContain('bodyspec_dexa');
    expect(modelContext[0].content).not.toContain('private');

    if (previous === undefined) delete process.env.LYB_COACH_PERSONA_GUARDRAILS_V1;
    else process.env.LYB_COACH_PERSONA_GUARDRAILS_V1 = previous;

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

  it('loads engine output only for training questions and keeps it server-scoped', async () => {
    const engineOutput: NextWorkoutResult = {
      kind: 'workout',
      week: 1,
      weekCount: 2,
      weeklyFractionalVolume: { chest: 4 },
      decision: holdDecision,
      session: {
        id: conversationId,
        week: 1,
        slot: 0,
        pattern: 'A',
        title: 'Full body A',
        safetyStop: false,
        explanation: null,
        evidenceIds: ['k:81c218db'],
        exercises: [
          {
            id: 'goblet_squat',
            name: 'Goblet squat',
            primaryMuscle: 'quads',
            muscleContribution: { quads: 1 },
            sets: 2,
            repRange: { min: 8, max: 12 },
            targetReps: 9,
            targetRir: 4,
            targetLoadKg: null,
            loadInstruction: null,
            progression: 'add_reps',
            evidenceIds: ['k:1795aef0'],
          },
        ],
      },
    };
    const { handlers, model, getTrainingOutput } = makeHarness(engineOutput);
    await (
      await handlers.POST(request('POST', 'user-a', chatBody('What is my next training session?')))
    ).text();
    expect(getTrainingOutput).toHaveBeenCalledWith('user-a');
    expect(model.calls[0]?.messages[0]?.content).toContain('"targetReps":9');
    expect(model.calls[0]?.messages[0]?.content).toContain('[k:1795aef0]');

    const nonTraining = makeHarness(engineOutput);
    await (
      await nonTraining.handlers.POST(
        request('POST', 'user-a', chatBody('Summarize my body trend.')),
      )
    ).text();
    expect(nonTraining.getTrainingOutput).not.toHaveBeenCalled();
    expect(nonTraining.model.calls[0]?.messages[0]?.content).not.toContain('targetReps');
  });

  it('withholds unsupported set, rep, and load numbers before streaming or persistence', async () => {
    const engineOutput: NextWorkoutResult = {
      kind: 'workout',
      week: 1,
      weekCount: 4,
      weeklyFractionalVolume: { chest: 4 },
      decision: holdDecision,
      session: {
        id: conversationId,
        week: 1,
        slot: 0,
        pattern: 'A',
        title: 'Full body A',
        safetyStop: false,
        explanation: null,
        evidenceIds: ['k:81c218db'],
        exercises: [
          {
            id: 'goblet_squat',
            name: 'Goblet squat',
            primaryMuscle: 'quads',
            muscleContribution: { quads: 1 },
            sets: 2,
            repRange: { min: 8, max: 12 },
            targetReps: 9,
            targetRir: 4,
            targetLoadKg: null,
            loadInstruction: null,
            progression: 'add_reps',
            evidenceIds: ['k:1795aef0'],
          },
        ],
      },
    };
    const { handlers, model, store } = makeHarness(engineOutput);
    model.chunks = ['Try 3 sets of 12 reps at 20 kg.'];

    const response = await handlers.POST(
      request('POST', 'user-a', chatBody('How many reps should I do for my workout?')),
    );
    const stream = await response.text();
    expect(stream).not.toContain('Try 3 sets');
    expect(stream).toContain('I cannot add quantities the engine did not return.');
    expect([...store.turns.values()][0]?.assistantMessage?.content).toContain(
      'I cannot add quantities the engine did not return.',
    );
  });

  it('withholds diagnosis and drug direction before streaming when the persona gate is on', async () => {
    const previous = process.env[COACH_PERSONA_GUARDRAILS_FLAG];
    process.env[COACH_PERSONA_GUARDRAILS_FLAG] = '1';
    try {
      const { handlers, model, store } = makeHarness();
      model.chunks = ['You have diabetes. ', 'Increase your semaglutide to 1 mg.'];
      const stream = await (
        await handlers.POST(request('POST', 'user-a', chatBody('What is wrong with me?')))
      ).text();
      expect(stream).not.toContain('You have diabetes');
      expect(stream).not.toContain('semaglutide');
      expect(stream).toContain("I can't diagnose a condition or prescribe medication");
      expect(model.calls[0]?.messages[0]?.content).toContain('Never diagnose a condition');
      expect(model.calls[0]?.messages[0]?.content).not.toContain('must not enter model context');
      expect([...store.turns.values()][0]?.assistantMessage?.content).toContain(
        "I can't diagnose a condition or prescribe medication",
      );
    } finally {
      if (previous === undefined) delete process.env[COACH_PERSONA_GUARDRAILS_FLAG];
      else process.env[COACH_PERSONA_GUARDRAILS_FLAG] = previous;
    }
  });

  it('streams engine-returned training quantities when the answer stays within the result', async () => {
    const engineOutput: NextWorkoutResult = {
      kind: 'workout',
      week: 1,
      weekCount: 4,
      weeklyFractionalVolume: { chest: 4 },
      decision: holdDecision,
      session: {
        id: conversationId,
        week: 1,
        slot: 0,
        pattern: 'A',
        title: 'Full body A',
        safetyStop: false,
        explanation: null,
        evidenceIds: ['k:81c218db'],
        exercises: [
          {
            id: 'goblet_squat',
            name: 'Goblet squat',
            primaryMuscle: 'quads',
            muscleContribution: { quads: 1 },
            sets: 2,
            repRange: { min: 8, max: 12 },
            targetReps: 9,
            targetRir: 4,
            targetLoadKg: null,
            loadInstruction: null,
            progression: 'add_reps',
            evidenceIds: ['k:1795aef0'],
          },
        ],
      },
    };
    const { handlers, model } = makeHarness(engineOutput);
    model.chunks = ['The engine returns 2 sets of 9 reps at 4 RIR.'];

    const stream = await (
      await handlers.POST(request('POST', 'user-a', chatBody('What is in my workout?')))
    ).text();
    expect(stream).toContain('The engine returns 2 sets of 9 reps at 4 RIR.');
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

  it('does not start the provider when a request is cancelled while context loads', async () => {
    const { handlers, model, store, getUser } = makeHarness();
    let releaseUser!: (value: ProductUserRecord) => void;
    let contextStarted!: () => void;
    const started = new Promise<void>((resolve) => {
      contextStarted = resolve;
    });
    getUser.mockImplementationOnce(
      () =>
        new Promise<ProductUserRecord>((resolve) => {
          releaseUser = resolve;
          contextStarted();
        }),
    );
    const abort = new AbortController();
    const cancelledRequest = new NextRequest(request('POST', 'user-a', chatBody()), {
      signal: abort.signal,
    });
    const pending = handlers.POST(cancelledRequest);
    await started;
    abort.abort();
    releaseUser(user('user-a'));
    const response = await pending;
    const body = await response.text();

    expect(model.calls).toHaveLength(0);
    expect(response.status).toBe(499);
    expect(body).not.toContain('event: done');
    expect([...store.turns.values()][0]?.status).toBe('cancelled');
    expect((await store.getLatest('user-a'))?.messages.map(({ role }) => role)).toEqual(['user']);

    const retried = await handlers.POST(request('POST', 'user-a', chatBody()));
    expect(await retried.text()).toContain('event: done');
    expect(model.calls).toHaveLength(1);
    expect((await store.getLatest('user-a'))?.messages.map(({ role }) => role)).toEqual([
      'user',
      'assistant',
    ]);
    expect(await store.getLatest('user-b')).toBeNull();
  });

  it('cancels an already-aborted request before reading context', async () => {
    const { handlers, model, store, getUser, listMetrics, reportStreamOutcome } = makeHarness();
    const abort = new AbortController();
    abort.abort();
    const response = await handlers.POST(
      new NextRequest(request('POST', 'user-a', chatBody()), {
        signal: abort.signal,
      }),
    );

    expect(response.status).toBe(499);
    expect(getUser).not.toHaveBeenCalled();
    expect(listMetrics).not.toHaveBeenCalled();
    expect(model.calls).toHaveLength(0);
    expect([...store.turns.values()][0]?.status).toBe('cancelled');
    expect(reportStreamOutcome.mock.calls).toEqual([['client_cancelled']]);
  });

  it('does not start the provider when training context finishes after cancellation', async () => {
    const { handlers, model, store, getTrainingOutput } = makeHarness();
    let releaseTraining!: (value: NextWorkoutResult | null) => void;
    let contextStarted!: () => void;
    const started = new Promise<void>((resolve) => {
      contextStarted = resolve;
    });
    getTrainingOutput.mockImplementationOnce(
      () =>
        new Promise<NextWorkoutResult | null>((resolve) => {
          releaseTraining = resolve;
          contextStarted();
        }),
    );
    const abort = new AbortController();
    const pending = handlers.POST(
      new NextRequest(request('POST', 'user-a', chatBody('What workout should I do?')), {
        signal: abort.signal,
      }),
    );
    await started;
    abort.abort();
    releaseTraining(null);
    const response = await pending;

    expect(response.status).toBe(499);
    expect(model.calls).toHaveLength(0);
    expect([...store.turns.values()][0]?.status).toBe('cancelled');
    expect((await store.getLatest('user-a'))?.messages.map(({ role }) => role)).toEqual(['user']);
  });

  it('keeps cancellation terminal when recording it fails', async () => {
    const { handlers, model, store, reportStreamOutcome } = makeHarness();
    jest.spyOn(store, 'failTurn').mockRejectedValue(new Error('private persistence detail'));
    const abort = new AbortController();
    abort.abort();
    const response = await handlers.POST(
      new NextRequest(request('POST', 'user-a', chatBody()), {
        signal: abort.signal,
      }),
    );

    expect(response.status).toBe(499);
    await expect(response.json()).resolves.toEqual({ version: 1, error: 'client_cancelled' });
    expect(model.calls).toHaveLength(0);
    expect(reportStreamOutcome.mock.calls).toEqual([
      ['client_cancelled'],
      ['failure_persistence_error'],
    ]);
  });

  it('retains context-failure recovery for a request that was not cancelled', async () => {
    const { handlers, model, store, getUser } = makeHarness();
    getUser.mockRejectedValueOnce(new Error('private context detail'));
    const response = await handlers.POST(request('POST', 'user-a', chatBody()));

    expect(response.status).toBe(503);
    expect(response.headers.get('retry-after')).toBe('5');
    await expect(response.json()).resolves.toEqual({ version: 1, error: 'chat_unavailable' });
    expect(model.calls).toHaveLength(0);
    expect([...store.turns.values()][0]?.status).toBe('failed');
    const retry = await handlers.POST(request('POST', 'user-a', chatBody()));
    expect(await retry.text()).toContain('event: done');
  });

  it.each([false, true])(
    'does not complete a provider that ends after cancellation (late delta: %s)',
    async (lateDelta) => {
      const { handlers, model, store, reportStreamOutcome } = makeHarness();
      const abort = new AbortController();
      jest.spyOn(model, 'streamText').mockImplementation(async function* () {
        yield { type: 'text_delta', text: 'Partial answer' };
        abort.abort();
        if (lateDelta) yield { type: 'text_delta', text: ' stale continuation' };
      });
      const response = await handlers.POST(
        new NextRequest(request('POST', 'user-a', chatBody()), { signal: abort.signal }),
      );
      const body = await response.text();

      expect(body).not.toContain('event: done');
      expect(body).not.toContain('stale continuation');
      expect([...store.turns.values()][0]?.status).toBe('cancelled');
      expect((await store.getLatest('user-a'))?.messages.map(({ role }) => role)).toEqual(['user']);
      expect(reportStreamOutcome).toHaveBeenCalledWith('client_cancelled');
      expect(reportStreamOutcome).not.toHaveBeenCalledWith('completed');
    },
  );

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

    const reloaded = await (await handlers.GET(request('GET', 'user-a'))).json();
    expect(reloaded.conversation.messages).toEqual([
      expect.objectContaining({
        clientMessageId,
        content: chatBody().message,
        turn: { status: 'failed', retryable: true },
      }),
    ]);
    expect(reloaded.conversation.id).toBe(conversationId);

    model.shouldFail = false;
    const retried = await handlers.POST(request('POST', 'user-a', chatBody()));
    expect(await retried.text()).toContain('event: done');
    const conversation = await store.getLatest('user-a');
    expect(conversation?.messages.filter(({ role }) => role === 'user')).toHaveLength(1);
    expect(conversation?.messages.filter(({ role }) => role === 'assistant')).toHaveLength(1);
    const completedHistory = await (await handlers.GET(request('GET', 'user-a'))).json();
    expect(completedHistory.conversation.messages[0].turn).toEqual({
      status: 'completed',
      retryable: false,
    });
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
