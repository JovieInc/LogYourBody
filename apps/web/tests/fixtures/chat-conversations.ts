import type {
  BeginChatTurnInput,
  ChatConversationPort,
  ChatRateLimitResult,
  StoredChatConversation,
  StoredChatMessage,
} from '@/lib/ports/chat-conversations';

const now = '2026-08-02T22:00:00.000Z';

type MemoryTurn = {
  id: string;
  owner: string;
  content: string;
  status: 'pending' | 'completed' | 'failed' | 'cancelled';
  leaseToken: string;
  userMessage: StoredChatMessage;
  assistantMessage?: StoredChatMessage;
};

export class MemoryConversationStore implements ChatConversationPort {
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
    const conversation = values.at(-1)?.conversation;
    if (!conversation) return null;
    return {
      ...conversation,
      messages: conversation.messages.map((message) => {
        const turn = this.turns.get(`${conversation.id}:${message.clientMessageId}`);
        return message.role === 'user' && turn && turn.owner === subject
          ? {
              ...message,
              turn: {
                status: turn.status,
                retryable: turn.status === 'failed' || turn.status === 'cancelled',
              },
            }
          : message;
      }),
    };
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
