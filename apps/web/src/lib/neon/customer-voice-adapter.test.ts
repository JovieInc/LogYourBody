/** @jest-environment node */
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonCustomerVoiceStore, neonCustomerVoice } from './customer-voice-adapter';
import { privateSupportSummary } from '@/lib/customer-voice/event';
import type { VoiceItem } from '@/lib/ports/customer-voice';
jest.mock('server-only', () => ({}));
const row = {
  id: '11111111-2222-4333-8444-555555555555',
  channel: 'email',
  received_at: '2026-10-31T00:00:00.000Z',
  reply_to: 'original@example.org',
  sender_hash: 'a'.repeat(64),
  ...privateSupportSummary('refund'),
  urgent_reasons: ['billing'],
  stages: { received: '2026-10-31T00:00:00.000Z' },
  test: false,
};
const voice: VoiceItem = {
  event: {
    schema: 'company.customer-voice/v1',
    app: 'logyourbody',
    id: row.id,
    channel: 'email',
    receivedAt: row.received_at,
    text: row.text,
    who: 'LogYourBody customer',
    replyable: true,
    urgent: true,
    urgentReasons: ['billing'],
    test: false,
  },
  senderHash: row.sender_hash,
  replyTo: row.reply_to,
  stages: row.stages,
};
function setup() {
  const query = jest.fn();
  const store = createNeonCustomerVoiceStore(query as unknown as NeonQueryFunction<false, false>);
  return { query, store };
}

it('binds all values and preserves the original immutable row on redelivery', async () => {
  const { query, store } = setup();
  query.mockResolvedValueOnce([row]);
  expect(await store.insert(voice)).toEqual(voice);
  expect(query.mock.calls[0][0].join('?')).toMatch(/on conflict \(id\) do nothing returning \*/);
  expect(query.mock.calls[0].slice(1)).toEqual([
    row.id,
    'email',
    row.received_at,
    row.sender_hash,
    row.reply_to,
    row.text,
    '["billing"]',
    JSON.stringify(row.stages),
    false,
  ]);
  query.mockResolvedValueOnce([]).mockResolvedValueOnce([row]);
  expect(await store.insert({ ...voice, replyTo: 'ignored@example.org' })).toEqual(voice);
  expect(query.mock.calls[2][0].join('?')).toMatch(/select \* from public.customer_voice_items/);
});
it('rejects conflicting identity and missing redelivery rows without replacing the recipient', async () => {
  const { query, store } = setup();
  query.mockResolvedValueOnce([]).mockResolvedValueOnce([]);
  await expect(store.insert(voice)).rejects.toThrow('persistence unavailable');
  for (const patch of [{ sender_hash: 'b'.repeat(64) }, { channel: 'chat' }]) {
    query.mockResolvedValueOnce([{ ...row, ...patch }]);
    await expect(store.insert(voice)).rejects.toThrow('identity conflict');
  }
});
it('reads nonreplyable rows and returns null for missing ids', async () => {
  const { query, store } = setup();
  query
    .mockResolvedValueOnce([{ ...row, reply_to: null, urgent_reasons: [] }])
    .mockResolvedValueOnce([]);
  expect((await store.get(row.id))?.event).toMatchObject({ replyable: false, urgent: false });
  expect(await store.get(row.id)).toBeNull();
});
it('merges timestamps with first-write-wins and atomically claims only an unsent original recipient', async () => {
  const { query, store } = setup();
  query
    .mockResolvedValueOnce([])
    .mockResolvedValueOnce([{ id: row.id }])
    .mockResolvedValueOnce([]);
  await store.stage(row.id, 'forwarded', row.received_at);
  expect(query.mock.calls[0][0].join('?')).toMatch(
    /jsonb_build_object\(\?::text, \?::text\) \|\| stages/,
  );
  const receipt = {
    approvedAt: row.received_at,
    approvalKey: 'photon-fixture',
    draftSha256: 'c'.repeat(64),
  };
  expect(await store.claimReply(row.id, receipt)).toBe(true);
  expect(await store.claimReply(row.id, receipt)).toBe(false);
  const statement = query.mock.calls[1][0].join('?');
  expect(statement).toContain('reply_to is not null');
  expect(statement).toContain("not (stages ? 'sent') and not (stages ? 'sending')");
  expect(query.mock.calls[1].slice(1)).toEqual([
    receipt.approvedAt,
    JSON.stringify(receipt),
    row.id,
  ]);
});
it('fails closed when database configuration is absent', async () => {
  const saved = process.env.DATABASE_URL;
  delete process.env.DATABASE_URL;
  try {
    await expect(neonCustomerVoice.get(row.id)).rejects.toThrow('Missing DATABASE_URL');
  } finally {
    if (saved !== undefined) process.env.DATABASE_URL = saved;
  }
});
