/**
 * @jest-environment node
 */
import { OpenAIChatModelAdapter } from '@/lib/adapters/openai-chat-model-adapter';
import type { ChatModelStreamEvent } from '@/lib/ports/chat-model';
import {
  elevenLabsZeroRetentionProviderOptions,
  gatewayZeroRetentionProviderOptions,
  isAiZeroRetentionEnabled,
} from '@/lib/ai/zero-retention';
import { createJsonCompletionPort } from '@/lib/ports/openai-json-completion';

jest.mock('server-only', () => ({}));

jest.mock('openai', () => {
  const create = jest.fn();
  const OpenAIClient = jest.fn().mockImplementation(() => ({
    chat: { completions: { create } },
  }));
  return { __esModule: true, default: OpenAIClient, create };
});

function openAiMock() {
  const mocked = jest.requireMock('openai') as {
    default: jest.Mock;
    create: jest.Mock;
  };
  return mocked;
}

describe('provider zero retention', () => {
  const previous = process.env.LYB_AI_ZERO_RETENTION;

  beforeEach(() => {
    const { create, default: OpenAIClient } = openAiMock();
    create.mockReset();
    OpenAIClient.mockClear();
    delete process.env.LYB_AI_ZERO_RETENTION;
  });

  afterAll(() => {
    if (previous === undefined) delete process.env.LYB_AI_ZERO_RETENTION;
    else process.env.LYB_AI_ZERO_RETENTION = previous;
  });

  it('leaves response-breaking provider options off by default', () => {
    expect(isAiZeroRetentionEnabled()).toBe(false);
    expect(elevenLabsZeroRetentionProviderOptions()).toBeUndefined();
    expect(gatewayZeroRetentionProviderOptions()).toBeUndefined();
  });

  it('sets ElevenLabs and gateway zero-retention options only when the flag is on', () => {
    process.env.LYB_AI_ZERO_RETENTION = '1';
    expect(elevenLabsZeroRetentionProviderOptions()).toEqual({
      elevenlabs: { enableLogging: false },
    });
    expect(gatewayZeroRetentionProviderOptions()).toEqual({
      gateway: { zeroDataRetention: true },
    });
    process.env.LYB_AI_ZERO_RETENTION = 'true';
    expect(isAiZeroRetentionEnabled()).toBe(false);
  });

  it('sends OpenAI chat completions with store false and without request logging', async () => {
    const { create, default: OpenAIClient } = openAiMock();
    create.mockResolvedValue({
      choices: [{ message: { content: '{"scans":[]}' } }],
    });
    const port = createJsonCompletionPort('test-key');
    await port.createJsonObjectCompletion({
      messages: [{ role: 'user', content: 'weight 180 lbs' }],
    });
    await port.createTextCompletion({
      messages: [{ role: 'user', content: 'weight 180 lbs' }],
      maxTokens: 20,
    });

    expect(OpenAIClient).toHaveBeenCalledWith({ apiKey: 'test-key', logLevel: 'off' });
    expect(create.mock.calls.map((call: unknown[]) => call[0])).toEqual([
      expect.objectContaining({
        store: false,
        messages: [{ role: 'user', content: 'weight 180 lbs' }],
      }),
      expect.objectContaining({ store: false, max_tokens: 20 }),
    ]);
  });

  it('streams chat completions with store false and does not log the prompt', async () => {
    const { create, default: OpenAIClient } = openAiMock();
    create.mockResolvedValue(
      (async function* () {
        yield { choices: [{ delta: { content: 'steady' } }] };
        yield { choices: [], usage: { prompt_tokens: 2, completion_tokens: 1 } };
      })(),
    );
    const debug = jest.spyOn(console, 'debug').mockImplementation(() => undefined);
    const info = jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const adapter = new OpenAIChatModelAdapter('chat-key', 'gpt-4o-mini');
    const events: ChatModelStreamEvent[] = [];
    for await (const event of adapter.streamText({
      messages: [{ role: 'user', content: 'body fat 18%' }],
      maxOutputTokens: 30,
      signal: new AbortController().signal,
    })) {
      events.push(event);
    }

    expect(OpenAIClient).toHaveBeenCalledWith({ apiKey: 'chat-key', logLevel: 'off' });
    expect(create.mock.calls[0][0]).toEqual(
      expect.objectContaining({
        store: false,
        model: 'gpt-4o-mini',
        messages: [{ role: 'user', content: 'body fat 18%' }],
      }),
    );
    expect(events).toEqual([
      { type: 'text_delta', text: 'steady' },
      { type: 'usage', inputTokens: 2, outputTokens: 1 },
    ]);
    expect(debug).not.toHaveBeenCalled();
    expect(info).not.toHaveBeenCalled();
    debug.mockRestore();
    info.mockRestore();
  });
});
