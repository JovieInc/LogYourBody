import 'server-only';

import { createHmac } from 'node:crypto';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { WAITLIST_RATE_LIMIT, type WaitlistRateLimitPort } from '@/lib/ports/waitlist-rate-limit';

let sql: NeonQueryFunction<false, false> | undefined;

export const neonWaitlistRateLimit: WaitlistRateLimitPort = {
  async reserve(clientIp) {
    // Use the product database: its existing deployment runner applies the
    // limiter migration. Waitlist email storage remains in its separate project.
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) throw new Error('Missing DATABASE_URL for waitlist rate limiting');
    sql ??= neon(connectionString);
    // Reuse an existing server secret with domain separation. Neither raw IPs
    // nor emails are persisted in the counter table or emitted as telemetry.
    const key = createHmac('sha256', connectionString)
      .update(`waitlist:v1:${clientIp}`)
      .digest('hex');
    const { attempts, windowSeconds } = WAITLIST_RATE_LIMIT;
    const rows = await sql`
      with expired as (
        delete from public.waitlist_rate_limits
        where client_key in (
          select client_key from public.waitlist_rate_limits
          where expires_at < now() - interval '1 day' and client_key <> ${key}
          limit 100
        )
      )
      insert into public.waitlist_rate_limits as limits (client_key, attempts, expires_at)
      values (${key}, 1, now() + ${windowSeconds} * interval '1 second')
      on conflict (client_key) do update set
        attempts = case when limits.expires_at <= now() then 1
          else least(limits.attempts + 1, ${attempts + 1}) end,
        expires_at = case when limits.expires_at <= now() then excluded.expires_at
          else limits.expires_at end
      returning attempts <= ${attempts} as allowed,
        greatest(1, ceil(extract(epoch from (expires_at - now()))))::integer as retry_after
    `;
    const row = rows[0];
    if (
      typeof row?.allowed !== 'boolean' ||
      !Number.isSafeInteger(row.retry_after) ||
      row.retry_after < 1
    ) {
      throw new Error('Invalid waitlist rate limit receipt');
    }
    return { allowed: row.allowed, retryAfterSeconds: row.retry_after };
  },
};
