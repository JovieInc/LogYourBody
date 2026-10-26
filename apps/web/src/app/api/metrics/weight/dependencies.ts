import { oauthIssuer } from '@/lib/auth/jovie-oauth';
import { delegatedMetricsEnabled } from '@/lib/flags/delegated-metrics';
import { endpoints } from '@/lib/generated/endpoints.generated';
import { createJwksSource, verifyAccessToken } from '@/lib/mcp/access-token';
import { mcpResourceUrl } from '@/lib/mcp/contract';
import { neonWeightLifecycle } from '@/lib/neon/weight-lifecycle-adapter';
import { createWeightRouteHandlers } from './route-handlers';

const issuer = oauthIssuer();
const jwks = createJwksSource({ url: `${issuer}/jwks` });

export const weightHandlers = createWeightRouteHandlers({
  enabled: () => delegatedMetricsEnabled(),
  authenticate: async (request) => {
    const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
    if (!token) return null;
    const resource = mcpResourceUrl(
      new URL(request.url).origin,
      process.env.VERCEL_ENV === 'production' ? endpoints.hosts.api.url : null,
    );
    const principal = await verifyAccessToken(token, {
      issuer,
      audience: resource,
      jwks,
      nowSeconds: Math.floor(Date.now() / 1000),
    });
    return principal ? { subject: principal.subject, scopes: principal.scopes } : null;
  },
  store: neonWeightLifecycle,
  now: () => new Date(),
});
