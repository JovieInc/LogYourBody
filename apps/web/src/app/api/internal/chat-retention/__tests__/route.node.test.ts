/** @jest-environment node */

import { NextRequest } from 'next/server';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { GET } from '../route';

jest.mock('@/lib/neon/chat-conversations-adapter', () => ({
  neonChatConversations: { purgeExpired: jest.fn() },
}));

describe('/api/internal/chat-retention', () => {
  const originalSecret = process.env.CRON_SECRET;

  afterEach(() => {
    jest.clearAllMocks();
    if (originalSecret === undefined) delete process.env.CRON_SECRET;
    else process.env.CRON_SECRET = originalSecret;
  });

  it('fails closed when the secret is missing or incorrect', async () => {
    delete process.env.CRON_SECRET;
    expect(
      (await GET(new NextRequest('http://localhost/api/internal/chat-retention'))).status,
    ).toBe(401);

    process.env.CRON_SECRET = 'fixture-secret';
    expect(
      (
        await GET(
          new NextRequest('http://localhost/api/internal/chat-retention', {
            headers: { authorization: 'Bearer wrong-secret' },
          }),
        )
      ).status,
    ).toBe(401);
    expect(neonChatConversations.purgeExpired).not.toHaveBeenCalled();
  });

  it('purges expired conversations for the authorized scheduler', async () => {
    process.env.CRON_SECRET = 'fixture-secret';
    jest.mocked(neonChatConversations.purgeExpired).mockResolvedValue(3);
    const response = await GET(
      new NextRequest('http://localhost/api/internal/chat-retention', {
        headers: { authorization: 'Bearer fixture-secret' },
      }),
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ ok: true, purged: 3 });
  });
});
