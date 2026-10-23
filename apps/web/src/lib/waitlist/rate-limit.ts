import { isIP } from 'node:net';
import { neonWaitlistRateLimit } from '@/lib/neon/waitlist-rate-limit-adapter';

export function reserveWaitlistRequest(headers: Headers) {
  // Vercel supplies this header itself. Never fall back to a caller-controlled
  // forwarding header in production. Other hosts must sanitize x-forwarded-for.
  const header = process.env.VERCEL === '1' ? 'x-vercel-forwarded-for' : 'x-forwarded-for';
  const value = headers.get(header)?.trim() ?? '';
  const version = value.includes('%') ? 0 : isIP(value);
  // Normalize equivalent IPv6 representations; missing/invalid IPs share a
  // restrictive bucket instead of bypassing the limit or trusting another header.
  const clientIp =
    version === 6 ? new URL(`http://[${value}]/`).hostname : version === 4 ? value : 'unknown';
  return neonWaitlistRateLimit.reserve(clientIp);
}
