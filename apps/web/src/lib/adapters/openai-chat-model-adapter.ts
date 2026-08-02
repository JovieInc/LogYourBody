import 'server-only';

import OpenAI from 'openai';
import type { ChatCompletionMessageParam } from 'openai/resources/chat/completions';
import type {
  ChatModelPort,
  ChatModelStreamEvent,
  ChatModelStreamRequest,
} from '@/lib/ports/chat-model';

export class OpenAIChatModelAdapter implements ChatModelPort {
  private readonly client: OpenAI;

  constructor(
    apiKey: string,
    private readonly model = process.env.LYB_CHAT_MODEL || 'gpt-4o-mini',
  ) {
    this.client = new OpenAI({ apiKey });
  }

  async *streamText({
    messages,
    maxOutputTokens,
    signal,
  }: ChatModelStreamRequest): AsyncIterable<ChatModelStreamEvent> {
    const stream = await this.client.chat.completions.create(
      {
        model: this.model,
        messages: messages as ChatCompletionMessageParam[],
        max_completion_tokens: maxOutputTokens,
        temperature: 0.2,
        stream: true,
        stream_options: { include_usage: true },
      },
      { signal },
    );

    for await (const chunk of stream) {
      const text = chunk.choices[0]?.delta?.content;
      if (text) yield { type: 'text_delta', text };
      if (chunk.usage) {
        yield {
          type: 'usage',
          inputTokens: chunk.usage.prompt_tokens,
          outputTokens: chunk.usage.completion_tokens,
        };
      }
    }
  }
}

export function createChatModelPort(): ChatModelPort {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('CHAT_MODEL_NOT_CONFIGURED');
  return new OpenAIChatModelAdapter(apiKey);
}
