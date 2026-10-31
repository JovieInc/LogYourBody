import { randomUUID } from 'node:crypto';
import { neonTrainingRevisions } from '@/lib/neon/training-revisions-adapter';
import { delegatedProgrammingEnabled } from '@/lib/flags/delegated-programming';
import { delegatedMetricsEnabled } from '@/lib/flags/delegated-metrics';
import { healthVaultEnabled } from '@/lib/flags/health-vault';
import { trainingMcpEnabled } from '@/lib/flags/training-mcp';
import { healthVaultService } from '../health-vault/dependencies';
import { neonWeightLifecycle } from '@/lib/neon/weight-lifecycle-adapter';
import { oauthIssuer } from '@/lib/auth/jovie-oauth';
import { endpoints } from '@/lib/generated/endpoints.generated';
import { createJwksSource } from '@/lib/mcp/access-token';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { createMcpRouteHandlers } from './route-handlers';

const issuer = oauthIssuer();

export const mcpHandlers = createMcpRouteHandlers({
  enabled: trainingMcpEnabled,
  issuer,
  canonicalApiOrigin: () =>
    process.env.VERCEL_ENV === 'production' ? endpoints.hosts.api.url : null,
  jwks: createJwksSource({ url: `${issuer}/jwks` }),
  records: neonNativeProductRecords,
  revisions: neonTrainingRevisions,
  delegatedEnabled: delegatedProgrammingEnabled,
  metricsEnabled: () => delegatedMetricsEnabled(),
  vaultEnabled: () => healthVaultEnabled(),
  vault: healthVaultService,
  weight: neonWeightLifecycle,
  reserveRequest: (subject) => neonChatConversations.reserveRequest(subject),
  now: () => new Date(),
  createId: randomUUID,
});
