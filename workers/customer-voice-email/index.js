import PostalMime from 'postal-mime';
import { privateSupportSummary } from '../../apps/web/src/lib/customer-voice/event.ts';
import { isAutomatedEmail } from '../../apps/web/src/lib/customer-voice/classify.ts';

const MAX_PARSE_BYTES = 1024 * 1024;
const encoder = new TextEncoder();
async function hmac(secret, value) {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(value)));
}
const hex = (bytes) => Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');

async function capture(message, env) {
  if (!env.INBOUND_URL || !env.CUSTOMER_VOICE_INBOUND_SECRET)
    throw new Error('capture-unconfigured');
  const url = new URL(env.INBOUND_URL);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash)
    throw new Error('capture-unconfigured');
  let text = '';
  // Large/malformed messages still produce a generic event; the original mailbox
  // forward is independent. Attachments, headers and bodies never enter the new capture request.
  if (message.rawSize <= MAX_PARSE_BYTES) {
    try {
      const parsed = await PostalMime.parse(message.raw);
      text = privateSupportSummary(parsed.text || parsed.html || '', parsed.subject).text;
    } catch {
      /* Capture the generic event without logging parser input/errors. */
    }
  }
  const subject = message.headers.get('subject') || '';
  const safeText = text || privateSupportSummary('', subject).text;
  // Stable opaque delivery id when Message-ID exists. No message-id or address
  // is exposed to Summer. A retry within this invocation reuses the exact body.
  const messageId = message.headers.get('message-id');
  const identity = messageId
    ? `${message.from.toLowerCase()}\n${message.to.toLowerCase()}\n${messageId}`
    : crypto.randomUUID();
  const bytes = (await hmac(env.CUSTOMER_VOICE_INBOUND_SECRET, identity)).slice(0, 16);
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const id = hex(bytes).replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, '$1-$2-$3-$4-$5');
  const body = JSON.stringify({
    id,
    receivedAt: new Date().toISOString(),
    from: message.from.toLowerCase(),
    text: safeText,
    automated: isAutomatedEmail({
      from: message.from,
      subject,
      headers: Object.fromEntries(
        ['auto-submitted', 'list-id', 'list-unsubscribe', 'precedence'].map((key) => [
          key,
          message.headers.get(key) || '',
        ]),
      ),
    }),
  });
  const signature = `sha256=${hex(await hmac(env.CUSTOMER_VOICE_INBOUND_SECRET, body))}`;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-customer-voice-signature': signature,
        },
        body,
        redirect: 'error',
        signal: AbortSignal.timeout(10000),
      });
      if (response.ok) return;
    } catch {
      /* Retry the same event without emitting sensitive errors. */
    }
  }
  throw new Error('customer-voice-capture-unavailable');
}

export default {
  async email(message, env) {
    if (!env.FORWARD_TO) throw new Error('forward-destination-unconfigured');
    // Always attempt BOTH operations, even if forwarding, parsing or capture fails.
    const results = await Promise.allSettled([
      message.forward(env.FORWARD_TO),
      capture(message, env),
    ]);
    if (results.some((result) => result.status === 'rejected'))
      throw new Error('customer-voice-delivery-incomplete');
  },
};
