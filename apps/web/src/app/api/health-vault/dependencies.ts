import { endpoints } from '@/lib/generated/endpoints.generated';
import { healthVaultEnabled } from '@/lib/flags/health-vault';
import { createHealthVaultHttpHandlers } from '@/lib/mcp/health-vault/http';
import { createProductVaultReader } from '@/lib/mcp/health-vault/reader';
import { createHealthVaultService } from '@/lib/mcp/health-vault/service';
import { neonBodyMetricsExport } from '@/lib/neon/body-metrics-adapter';
import { createNeonHealthVaultStore, healthVaultMediaReader } from '@/lib/neon/health-vault-store';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';

/**
 * Shared by the MCP route and the vault HTTP routes so a handle minted by
 * open_health_vault redeems on the widget's direct request. The handle is the
 * credential. These HTTP routes do not accept a bearer token.
 */
const now = () => new Date();
const store = createNeonHealthVaultStore();

export const healthVaultService = createHealthVaultService({
  reader: createProductVaultReader({
    records: neonNativeProductRecords,
    bodyMetrics: neonBodyMetricsExport,
    apiOrigin: endpoints.hosts.api.url,
  }),
  store,
  now,
});

export const healthVaultHttp = createHealthVaultHttpHandlers({
  enabled: () => healthVaultEnabled(),
  service: healthVaultService,
  media: healthVaultMediaReader(store, now),
  apiOrigin: (request) =>
    process.env.VERCEL_ENV === 'production' ? endpoints.hosts.api.url : new URL(request.url).origin,
});
