import OpenAI from 'openai';
import type { ChatCompletionMessageParam } from 'openai/resources/chat/completions';

interface JsonCompletionRequest {
  messages: ChatCompletionMessageParam[];
  model?: string;
  temperature?: number;
}

export interface JsonCompletionPort {
  createJsonObjectCompletion(request: JsonCompletionRequest): Promise<string>;
  createTextCompletion(request: JsonCompletionRequest & { maxTokens?: number }): Promise<string>;
}

class OpenAIJsonCompletionAdapter implements JsonCompletionPort {
  private readonly client: OpenAI;

  constructor(apiKey: string) {
    this.client = new OpenAI({ apiKey });
  }

  async createJsonObjectCompletion({
    messages,
    model = 'gpt-4o-mini',
    temperature = 0.1,
  }: JsonCompletionRequest): Promise<string> {
    const completion = await this.client.chat.completions.create({
      model,
      messages,
      response_format: { type: 'json_object' },
      temperature,
    });

    return completion.choices[0].message.content || '{}';
  }

  async createTextCompletion({
    messages,
    model = 'gpt-4o-mini',
    temperature = 0.1,
    maxTokens,
  }: JsonCompletionRequest & { maxTokens?: number }): Promise<string> {
    const completion = await this.client.chat.completions.create({
      model,
      messages,
      temperature,
      max_tokens: maxTokens,
    });

    return completion.choices[0]?.message?.content || '';
  }
}

export function createJsonCompletionPort(apiKey: string): JsonCompletionPort {
  return new OpenAIJsonCompletionAdapter(apiKey);
}
