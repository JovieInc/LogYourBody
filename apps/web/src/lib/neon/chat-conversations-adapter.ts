import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type {
  BeginChatTurnInput,
  BeginChatTurnResult,
  ChatConversationPort,
  ChatRateLimitResult,
  StoredChatConversation,
  StoredChatMessage,
} from '@/lib/ports/chat-conversations';

const WINDOW_LIMIT = 12;
const DAILY_LIMIT = 100;

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

type ConversationRow = {
  id: string;
  title: string;
  created_at: Date | string;
  updated_at: Date | string;
  expires_at: Date | string;
};

type MessageRow = {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  client_message_id: string | null;
  created_at: Date | string;
};

type TurnRow = {
  id: string;
  status: 'pending' | 'completed' | 'failed' | 'cancelled';
  lease_expires_at: Date | string | null;
  user_content: string | null;
  assistant_id: string | null;
  assistant_content: string | null;
  assistant_created_at: Date | string | null;
};

function iso(value: Date | string): string {
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function mapMessage(row: MessageRow): StoredChatMessage {
  return {
    id: row.id,
    role: row.role,
    content: row.content,
    clientMessageId: row.client_message_id,
    createdAt: iso(row.created_at),
  };
}

function mapConversation(row: ConversationRow, messages: MessageRow[]): StoredChatConversation {
  return {
    id: row.id,
    title: row.title,
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at),
    expiresAt: iso(row.expires_at),
    messages: messages.map(mapMessage),
  };
}

async function getConversation(
  database: NeonQueryFunction<false, false>,
  subject: string,
  conversationId: string,
): Promise<StoredChatConversation | null> {
  const conversations = (await database.query(
    `select id, title, created_at, updated_at, expires_at
     from public.chat_conversations
     where id = $1 and user_subject = $2 and expires_at > now()
     limit 1`,
    [conversationId, subject],
  )) as ConversationRow[];
  const conversation = conversations[0];
  if (!conversation) return null;

  const messages = (await database.query(
    `select id, role, content, client_message_id, created_at
     from (
       select id, role, content, client_message_id, created_at
       from public.chat_messages
       where conversation_id = $1 and user_subject = $2
       order by created_at desc, id desc
       limit 100
     ) recent_messages
     order by created_at asc, id asc`,
    [conversationId, subject],
  )) as MessageRow[];
  return mapConversation(conversation, messages);
}

async function findTurn(
  database: NeonQueryFunction<false, false>,
  subject: string,
  conversationId: string,
  clientMessageId: string,
): Promise<TurnRow | null> {
  const rows = (await database.query(
    `select
       turns.id,
       turns.status,
       turns.lease_expires_at,
       user_message.content as user_content,
       assistant_message.id as assistant_id,
       assistant_message.content as assistant_content,
       assistant_message.created_at as assistant_created_at
     from public.chat_turns turns
     join public.chat_conversations conversations
       on conversations.id = turns.conversation_id
      and conversations.user_subject = turns.user_subject
     left join public.chat_messages user_message
       on user_message.turn_id = turns.id and user_message.role = 'user'
     left join public.chat_messages assistant_message
       on assistant_message.turn_id = turns.id and assistant_message.role = 'assistant'
     where turns.conversation_id = $1
       and turns.user_subject = $2
       and turns.client_message_id = $3
       and conversations.expires_at > now()
     limit 1`,
    [conversationId, subject, clientMessageId],
  )) as TurnRow[];
  return rows[0] ?? null;
}

function replayResult(conversationId: string, turn: TurnRow): BeginChatTurnResult | null {
  if (
    turn.status !== 'completed' ||
    !turn.assistant_id ||
    !turn.assistant_content ||
    !turn.assistant_created_at
  ) {
    return null;
  }
  return {
    kind: 'replay',
    conversationId,
    assistantMessage: {
      id: turn.assistant_id,
      role: 'assistant',
      content: turn.assistant_content,
      clientMessageId: null,
      createdAt: iso(turn.assistant_created_at),
    },
  };
}

async function claimExistingTurn(
  database: NeonQueryFunction<false, false>,
  input: BeginChatTurnInput,
  turn: TurnRow,
): Promise<boolean> {
  const claimed = (await database.query(
    `update public.chat_turns
     set status = 'pending',
         lease_token = $3,
         lease_expires_at = now() + interval '2 minutes',
         failure_code = null,
         updated_at = now()
     where id = $1
       and user_subject = $2
       and (
         status in ('failed', 'cancelled') or
         (status = 'pending' and lease_expires_at <= now())
       )
     returning id`,
    [turn.id, input.subject, input.leaseToken],
  )) as Array<{ id: string }>;
  return Boolean(claimed[0]);
}

export function createNeonChatConversationStore(
  database: NeonQueryFunction<false, false> = getDatabase(),
): ChatConversationPort {
  return {
    async purgeExpired() {
      const conversations = (await database.query(
        `delete from public.chat_conversations
         where expires_at <= now()
         returning id`,
        [],
      )) as Array<{ id: string }>;
      const usageLimits = (await database.query(
        `delete from public.chat_usage_limits
         where updated_at <= now() - interval '30 days'
         returning user_subject`,
        [],
      )) as Array<{ user_subject: string }>;
      return conversations.length + usageLimits.length;
    },

    async getLatest(subject) {
      const conversations = (await database.query(
        `select id, title, created_at, updated_at, expires_at
         from public.chat_conversations
         where user_subject = $1 and expires_at > now()
         order by updated_at desc
         limit 1`,
        [subject],
      )) as ConversationRow[];
      const conversation = conversations[0];
      if (!conversation) return null;
      return getConversation(database, subject, conversation.id);
    },

    async beginTurn(input) {
      await database.query(
        `insert into public.chat_conversations (id, user_subject, title)
         values ($1, $2, $3)
         on conflict (id) do nothing`,
        [input.conversationId, input.subject, input.title],
      );

      const conversation = await getConversation(database, input.subject, input.conversationId);
      if (!conversation) return { kind: 'not_found' };

      let turn = await findTurn(
        database,
        input.subject,
        input.conversationId,
        input.clientMessageId,
      );

      if (turn) {
        if (turn.user_content && turn.user_content !== input.content) {
          return { kind: 'idempotency_conflict' };
        }
        const replay = replayResult(input.conversationId, turn);
        if (replay) return replay;

        const leaseExpiry = turn.lease_expires_at ? new Date(turn.lease_expires_at) : null;
        if (turn.status === 'pending' && leaseExpiry && leaseExpiry.getTime() > Date.now()) {
          return { kind: 'in_progress' };
        }
        if (!(await claimExistingTurn(database, input, turn))) {
          return { kind: 'in_progress' };
        }
      } else {
        const inserted = (await database.query(
          `insert into public.chat_turns (
             conversation_id, user_subject, client_message_id,
             status, lease_token, lease_expires_at
           ) values ($1, $2, $3, 'pending', $4, now() + interval '2 minutes')
           on conflict (conversation_id, user_subject, client_message_id) do nothing
           returning id`,
          [input.conversationId, input.subject, input.clientMessageId, input.leaseToken],
        )) as Array<{ id: string }>;

        if (!inserted[0]) {
          turn = await findTurn(
            database,
            input.subject,
            input.conversationId,
            input.clientMessageId,
          );
          if (!turn) return { kind: 'not_found' };
          if (turn.user_content && turn.user_content !== input.content) {
            return { kind: 'idempotency_conflict' };
          }
          const replay = replayResult(input.conversationId, turn);
          return replay ?? { kind: 'in_progress' };
        }

        turn = {
          id: inserted[0].id,
          status: 'pending',
          lease_expires_at: null,
          user_content: null,
          assistant_id: null,
          assistant_content: null,
          assistant_created_at: null,
        };
      }

      await database.query(
        `insert into public.chat_messages (
           turn_id, conversation_id, user_subject, role, content, client_message_id
         ) values ($1, $2, $3, 'user', $4, $5)
         on conflict (turn_id, role) do nothing`,
        [turn.id, input.conversationId, input.subject, input.content, input.clientMessageId],
      );

      const persistedTurn = await findTurn(
        database,
        input.subject,
        input.conversationId,
        input.clientMessageId,
      );
      if (!persistedTurn || persistedTurn.user_content !== input.content) {
        return { kind: 'idempotency_conflict' };
      }

      await database.query(
        `update public.chat_conversations
         set updated_at = now(), expires_at = now() + interval '30 days'
         where id = $1 and user_subject = $2`,
        [input.conversationId, input.subject],
      );

      const updatedConversation = await getConversation(
        database,
        input.subject,
        input.conversationId,
      );
      if (!updatedConversation) return { kind: 'not_found' };

      return {
        kind: 'claimed',
        conversation: updatedConversation,
        turnId: turn.id,
        leaseToken: input.leaseToken,
      };
    },

    async reserveRequest(subject): Promise<ChatRateLimitResult> {
      const rows = (await database.query(
        `insert into public.chat_usage_limits (
           user_subject, window_started_at, window_count,
           day_started_at, day_count, updated_at
         ) values ($1, now(), 1, now(), 1, now())
         on conflict (user_subject) do update set
           window_started_at = case
             when chat_usage_limits.window_started_at <= now() - interval '10 minutes'
             then now() else chat_usage_limits.window_started_at end,
           window_count = case
             when chat_usage_limits.window_started_at <= now() - interval '10 minutes'
             then 1 else chat_usage_limits.window_count + 1 end,
           day_started_at = case
             when chat_usage_limits.day_started_at <= now() - interval '1 day'
             then now() else chat_usage_limits.day_started_at end,
           day_count = case
             when chat_usage_limits.day_started_at <= now() - interval '1 day'
             then 1 else chat_usage_limits.day_count + 1 end,
           updated_at = now()
         where
           (chat_usage_limits.window_started_at <= now() - interval '10 minutes'
             or chat_usage_limits.window_count < $2)
           and
           (chat_usage_limits.day_started_at <= now() - interval '1 day'
             or chat_usage_limits.day_count < $3)
         returning window_count, day_count`,
        [subject, WINDOW_LIMIT, DAILY_LIMIT],
      )) as Array<{ window_count: number; day_count: number }>;

      const row = rows[0];
      if (row) {
        return {
          allowed: true,
          remainingInWindow: Math.max(0, WINDOW_LIMIT - Number(row.window_count)),
          remainingToday: Math.max(0, DAILY_LIMIT - Number(row.day_count)),
        };
      }

      const retryRows = (await database.query(
        `select greatest(
           case when window_count >= $2 then
             ceil(extract(epoch from (window_started_at + interval '10 minutes' - now())))
           else 1 end,
           case when day_count >= $3 then
             ceil(extract(epoch from (day_started_at + interval '1 day' - now())))
           else 1 end,
           1
         )::integer as retry_after
         from public.chat_usage_limits
         where user_subject = $1`,
        [subject, WINDOW_LIMIT, DAILY_LIMIT],
      )) as Array<{ retry_after: number }>;
      return { allowed: false, retryAfterSeconds: retryRows[0]?.retry_after ?? 60 };
    },

    async completeTurn(input) {
      const rows = (await database.query(
        `with completed_turn as (
           update public.chat_turns turns
           set status = 'completed',
               lease_token = null,
               lease_expires_at = null,
               failure_code = null,
               model = $4,
               input_tokens = $5,
               output_tokens = $6,
               updated_at = now()
           where turns.id = $1
             and turns.user_subject = $2
             and turns.lease_token = $3
             and turns.status = 'pending'
           returning turns.id, turns.conversation_id, turns.user_subject
         ), inserted_message as (
           insert into public.chat_messages (
             turn_id, conversation_id, user_subject, role, content, client_message_id
           )
           select id, conversation_id, user_subject, 'assistant', $7, null
           from completed_turn
           on conflict (turn_id, role) do update set content = excluded.content
           returning id, role, content, client_message_id, created_at
         )
         select id, role, content, client_message_id, created_at
         from inserted_message`,
        [
          input.turnId,
          input.subject,
          input.leaseToken,
          input.model,
          input.inputTokens,
          input.outputTokens,
          input.content,
        ],
      )) as MessageRow[];
      if (!rows[0]) throw new Error('CHAT_TURN_NOT_OWNED');

      await database.query(
        `update public.chat_conversations conversations
         set updated_at = now(), expires_at = now() + interval '30 days'
         from public.chat_turns turns
         where turns.id = $1
           and turns.user_subject = $2
           and conversations.id = turns.conversation_id
           and conversations.user_subject = turns.user_subject`,
        [input.turnId, input.subject],
      );
      return mapMessage(rows[0]);
    },

    async failTurn(input) {
      await database.query(
        `update public.chat_turns
         set status = $4,
             lease_token = null,
             lease_expires_at = null,
             failure_code = $5,
             updated_at = now()
         where id = $1
           and user_subject = $2
           and lease_token = $3
           and status = 'pending'`,
        [input.turnId, input.subject, input.leaseToken, input.status, input.failureCode],
      );
    },

    async deleteConversation(subject, conversationId) {
      const rows = (await database.query(
        `delete from public.chat_conversations
         where id = $1 and user_subject = $2
         returning id`,
        [conversationId, subject],
      )) as Array<{ id: string }>;
      return Boolean(rows[0]);
    },
  };
}

export const neonChatConversations: ChatConversationPort = {
  purgeExpired: () => createNeonChatConversationStore().purgeExpired(),
  getLatest: (subject) => createNeonChatConversationStore().getLatest(subject),
  beginTurn: (input) => createNeonChatConversationStore().beginTurn(input),
  reserveRequest: (subject) => createNeonChatConversationStore().reserveRequest(subject),
  completeTurn: (input) => createNeonChatConversationStore().completeTurn(input),
  failTurn: (input) => createNeonChatConversationStore().failTurn(input),
  deleteConversation: (subject, conversationId) =>
    createNeonChatConversationStore().deleteConversation(subject, conversationId),
};
