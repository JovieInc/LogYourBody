/** @jest-environment node */

import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonChatConversationStore } from './chat-conversations-adapter';

function databaseWith(query: jest.Mock) {
  return { query } as unknown as NeonQueryFunction<false, false>;
}

function normalized(statement: unknown) {
  return String(statement).replace(/\s+/g, ' ').trim();
}

describe('createNeonChatConversationStore', () => {
  it('scopes conversation lookup and message hydration to the authenticated subject', async () => {
    const conversationRow = {
      id: '11111111-1111-4111-8111-111111111111',
      title: 'How am I doing?',
      created_at: '2026-08-02T22:00:00.000Z',
      updated_at: '2026-08-02T22:01:00.000Z',
      expires_at: '2026-09-01T22:01:00.000Z',
    };
    const query = jest
      .fn()
      .mockResolvedValueOnce([conversationRow])
      .mockResolvedValueOnce([conversationRow])
      .mockResolvedValueOnce([
        {
          id: 'message-1',
          role: 'user',
          content: 'How am I doing?',
          client_message_id: '22222222-2222-4222-8222-222222222222',
          created_at: '2026-08-02T22:00:00.000Z',
        },
      ]);
    const store = createNeonChatConversationStore(databaseWith(query));

    const conversation = await store.getLatest('owner-subject');

    expect(conversation?.messages).toHaveLength(1);
    expect(normalized(query.mock.calls[0]?.[0])).toContain('where user_subject = $1');
    expect(query.mock.calls[0]?.[1]).toEqual(['owner-subject']);
    expect(normalized(query.mock.calls[1]?.[0])).toContain('where id = $1 and user_subject = $2');
    expect(query.mock.calls[1]?.[1]).toEqual([
      '11111111-1111-4111-8111-111111111111',
      'owner-subject',
    ]);
    expect(normalized(query.mock.calls[2]?.[0])).toContain(
      'where conversation_id = $1 and user_subject = $2',
    );
    expect(normalized(query.mock.calls[2]?.[0])).toContain('limit 100');
    expect(query.mock.calls[2]?.[1]).toEqual([
      '11111111-1111-4111-8111-111111111111',
      'owner-subject',
    ]);
  });

  it('requires both conversation id and owner subject for deletion', async () => {
    const query = jest.fn().mockResolvedValue([{ id: 'conversation-id' }]);
    const store = createNeonChatConversationStore(databaseWith(query));

    await expect(store.deleteConversation('owner-subject', 'conversation-id')).resolves.toBe(true);
    expect(normalized(query.mock.calls[0]?.[0])).toContain('where id = $1 and user_subject = $2');
    expect(query.mock.calls[0]?.[1]).toEqual(['conversation-id', 'owner-subject']);
  });

  it('purges expired conversations and inactive per-subject usage state', async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce([{ id: 'expired-conversation' }])
      .mockResolvedValueOnce([{ user_subject: 'inactive-subject' }]);
    const store = createNeonChatConversationStore(databaseWith(query));

    await expect(store.purgeExpired()).resolves.toBe(2);
    expect(normalized(query.mock.calls[0]?.[0])).toContain('where expires_at <= now()');
    expect(normalized(query.mock.calls[1]?.[0])).toContain(
      "where updated_at <= now() - interval '30 days'",
    );
  });
});
