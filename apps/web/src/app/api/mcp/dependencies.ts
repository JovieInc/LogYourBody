import { randomUUID } from 'node:crypto';
import { oauthIssuer } from '@/lib/auth/jovie-oauth';
import { endpoints } from '@/lib/generated/endpoints.generated';
import { createJwksSource } from '@/lib/mcp/access-token';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { createMcpRouteHandlers } from './route-handlers';

const issuer = oauthIssuer();

export const mcpHandlers = createMcpRouteHandlers({
  // Both switches: the MCP door and the training API it fronts.
  enabled: () =>
    process.env.LYB_CHATGPT_MCP_ENABLED === 'true' &&
    process.env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true',
  issuer,
  canonicalApiOrigin: () =>
    process.env.VERCEL_ENV === 'production' ? endpoints.hosts.api.url : null,
  jwks: createJwksSource({ url: `${issuer}/jwks` }),
  records: neonNativeProductRecords,
  reserveRequest: (subject) => neonChatConversations.reserveRequest(subject),
  now: () => new Date(),
  createId: randomUUID,
});
