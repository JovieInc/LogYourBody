export type ChatModelMessage = {
  role: 'system' | 'user' | 'assistant';
  content: string;
};

export type ChatModelStreamEvent =
  | { type: 'text_delta'; text: string }
  | { type: 'usage'; inputTokens: number; outputTokens: number };

export type ChatModelStreamRequest = {
  messages: ChatModelMessage[];
  maxOutputTokens: number;
  signal: AbortSignal;
};

export interface ChatModelPort {
  streamText(request: ChatModelStreamRequest): AsyncIterable<ChatModelStreamEvent>;
}
