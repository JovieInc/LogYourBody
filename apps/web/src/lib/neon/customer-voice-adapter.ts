import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { customerVoiceEventSchema } from '@/lib/customer-voice/event';
import type { CustomerVoiceStore, VoiceItem } from '@/lib/ports/customer-voice';

let sql: NeonQueryFunction<false, false> | undefined;
function getDatabase() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('Missing DATABASE_URL for customer voice');
  return (sql ??= neon(url));
}

type Row = {
  id: string;
  channel: string;
  received_at: string | Date;
  sender_hash: string | null;
  reply_to: string | null;
  text: string;
  urgent_reasons: string[];
  stages: VoiceItem['stages'];
  test: boolean;
};
function item(row: Row): VoiceItem {
  return {
    event: customerVoiceEventSchema.parse({
      schema: 'company.customer-voice/v1',
      app: 'logyourbody',
      id: row.id,
      channel: row.channel,
      receivedAt: new Date(row.received_at).toISOString(),
      text: row.text,
      who: 'LogYourBody customer',
      replyable: row.reply_to !== null,
      urgent: row.urgent_reasons.length > 0,
      urgentReasons: row.urgent_reasons,
      test: row.test,
    }),
    senderHash: row.sender_hash,
    replyTo: row.reply_to,
    stages: row.stages,
  };
}

export function createNeonCustomerVoiceStore(
  database?: NeonQueryFunction<false, false>,
): CustomerVoiceStore {
  const db = () => database ?? getDatabase();
  const store: CustomerVoiceStore = {
    async insert(value) {
      const e = value.event;
      const rows = await db()`
        insert into public.customer_voice_items
          (id, channel, received_at, sender_hash, reply_to, text, urgent_reasons, stages, test)
        values (${e.id}, ${e.channel}, ${e.receivedAt}, ${value.senderHash}, ${value.replyTo},
          ${e.text}, ${JSON.stringify(e.urgentReasons)}::jsonb, ${JSON.stringify(value.stages)}::jsonb, ${e.test})
        on conflict (id) do nothing returning *
      `;
      const saved = rows[0] ? item(rows[0] as Row) : await store.get(e.id);
      if (!saved) throw new Error('Customer voice persistence unavailable');
      // An authenticated replay must never replace the original recipient.
      if (saved.senderHash !== value.senderHash || saved.event.channel !== e.channel)
        throw new Error('Customer voice identity conflict');
      return saved;
    },
    async get(id) {
      const rows = await db()`select * from public.customer_voice_items where id = ${id}`;
      return rows[0] ? item(rows[0] as Row) : null;
    },
    async stage(id, stage, at) {
      await db()`update public.customer_voice_items
        set stages = jsonb_build_object(${stage}::text, ${at}::text) || stages
        where id = ${id}`;
    },
    async claimReply(id, receipt) {
      const rows = await db()`update public.customer_voice_items
        set stages = stages || jsonb_build_object('approved', ${receipt.approvedAt}::text, 'sending', now()::text),
          approval_receipt = ${JSON.stringify(receipt)}::jsonb
        where id = ${id} and reply_to is not null
          and not (stages ? 'sent') and not (stages ? 'sending')
        returning id`;
      return rows.length === 1;
    },
  };
  return store;
}
export const neonCustomerVoice = createNeonCustomerVoiceStore();
