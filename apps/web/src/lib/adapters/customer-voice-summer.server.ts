import 'server-only';
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import type { CustomerVoiceHandoff } from '@/lib/ports/customer-voice';
import { customerVoiceEventSchema, privateSupportSummary } from '@/lib/customer-voice/event';

// Same production identity constraints as Jovie's summer-oidc.server.ts.
export const SUMMER_OIDC = {
  issuer: 'https://oidc.vercel.com/jovie',
  audience: 'https://vercel.com/jovie',
  subject: 'owner:jovie:project:jovie-eve-shadow:environment:production',
  projectId: 'prj_LaVQva346cjp5XfrbAIIQUln7tPH',
} as const;
let keys: JWTVerifyGetKey | undefined;
export async function verifySummerOidcRequest(
  request: Request,
  key?: JWTVerifyGetKey,
): Promise<boolean> {
  const token = request.headers
    .get('authorization')
    ?.match(/^Bearer ([A-Za-z0-9_.-]{16,8192})$/)?.[1];
  if (!token) return false;
  try {
    const resolver =
      key ??
      (keys ??= createRemoteJWKSet(new URL(`${SUMMER_OIDC.issuer}/.well-known/jwks`), {
        timeoutDuration: 5000,
        cooldownDuration: 30000,
      }));
    const { payload } = await jwtVerify(token, resolver, {
      issuer: SUMMER_OIDC.issuer,
      audience: SUMMER_OIDC.audience,
      subject: SUMMER_OIDC.subject,
      algorithms: ['RS256'],
      clockTolerance: 60,
      requiredClaims: ['exp', 'iat'],
    });
    return payload.project_id === SUMMER_OIDC.projectId;
  } catch {
    return false;
  }
}

export function createSummerVoiceHandoff(
  env: NodeJS.ProcessEnv = process.env,
  fetchImpl: typeof fetch = fetch,
): CustomerVoiceHandoff {
  return {
    async forward(input) {
      const parsed = customerVoiceEventSchema.parse(input);
      // Defense at the external boundary as well as capture: optional freeform
      // subject/name/who must never leak health details from a future caller.
      const summary = privateSupportSummary(parsed.text, parsed.subject);
      const event = customerVoiceEventSchema.parse({
        schema: parsed.schema,
        app: parsed.app,
        id: parsed.id,
        channel: parsed.channel,
        receivedAt: parsed.receivedAt,
        ...summary,
        who: 'LogYourBody customer',
        replyable: parsed.replyable,
        urgent: summary.urgentReasons.length > 0,
        test: parsed.test,
      });
      const token = env.VERCEL_OIDC_TOKEN;
      if (!env.SUMMER_BASE_URL || !token) throw new Error('handoff-unavailable');
      const origin = new URL(env.SUMMER_BASE_URL);
      if (
        origin.protocol !== 'https:' ||
        origin.username ||
        origin.password ||
        origin.search ||
        origin.hash ||
        origin.pathname !== '/'
      )
        throw new Error('handoff-unavailable');
      const response = await fetchImpl(new URL('/ovie/v1/customer-voice/events', origin), {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${token}`,
          'x-vercel-trusted-oidc-idp-token': token,
        },
        body: JSON.stringify(event),
        redirect: 'error',
        cache: 'no-store',
        signal: AbortSignal.timeout(10000),
      });
      // A successful HTTP status alone does not prove Summer accepted the event.
      const body = await response.json();
      const result = body?.result;
      if (!response.ok || !['pinged', 'digested', 'replay'].includes(result?.status))
        throw new Error('handoff-unavailable');
      if (result.status === 'pinged') {
        if (typeof result.pingedAt !== 'string' || !Number.isFinite(Date.parse(result.pingedAt)))
          throw new Error('handoff-unavailable');
        return { pingedAt: new Date(result.pingedAt).toISOString() };
      }
      return {};
    },
  };
}
