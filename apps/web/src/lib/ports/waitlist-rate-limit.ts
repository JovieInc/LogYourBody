export const WAITLIST_RATE_LIMIT = { attempts: 5, windowSeconds: 600 } as const;

export interface WaitlistRateLimitPort {
  reserve(clientIp: string): Promise<{ allowed: boolean; retryAfterSeconds: number }>;
}
