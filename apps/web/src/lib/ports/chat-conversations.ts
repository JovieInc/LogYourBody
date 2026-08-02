export const CHAT_PROTOCOL_VERSION = 1 as const;
export const CHAT_RETENTION_DAYS = 30;

export type ChatRole = 'user' | 'assistant';
export type ChatTurnStatus = 'pending' | 'completed' | 'failed' | 'cancelled';

export type StoredChatMessage = {
  id: string;
  role: ChatRole;
  content: string;
  clientMessageId: string | null;
  createdAt: string;
};

export type StoredChatConversation = {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  expiresAt: string;
  messages: StoredChatMessage[];
};

export type BeginChatTurnInput = {
  subject: string;
  conversationId: string;
  clientMessageId: string;
  content: string;
  title: string;
  leaseToken: string;
};

export type BeginChatTurnResult =
  | {
      kind: 'claimed';
      conversation: StoredChatConversation;
      turnId: string;
      leaseToken: string;
    }
  | {
      kind: 'replay';
      conversationId: string;
      assistantMessage: StoredChatMessage;
    }
  | { kind: 'in_progress' }
  | { kind: 'idempotency_conflict' }
  | { kind: 'not_found' };

export type ChatRateLimitResult =
  | { allowed: true; remainingInWindow: number; remainingToday: number }
  | { allowed: false; retryAfterSeconds: number };

export interface ChatConversationPort {
  purgeExpired(): Promise<number>;
  getLatest(subject: string): Promise<StoredChatConversation | null>;
  beginTurn(input: BeginChatTurnInput): Promise<BeginChatTurnResult>;
  reserveRequest(subject: string): Promise<ChatRateLimitResult>;
  completeTurn(input: {
    subject: string;
    turnId: string;
    leaseToken: string;
    content: string;
    model: string;
    inputTokens: number | null;
    outputTokens: number | null;
  }): Promise<StoredChatMessage>;
  failTurn(input: {
    subject: string;
    turnId: string;
    leaseToken: string;
    status: 'failed' | 'cancelled';
    failureCode: string;
  }): Promise<void>;
  deleteConversation(subject: string, conversationId: string): Promise<boolean>;
}
