import { NextResponse } from 'next/server';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import { verifyAccessToken, type JwksSource } from '@/lib/mcp/access-token';
import { mcpResourceUrl, protectedResourceMetadata } from '@/lib/mcp/contract';
import { handleMcpRequest, unauthenticatedResult, type McpHttpResult } from '@/lib/mcp/handler';

type McpRouteDependencies = {
  enabled: () => boolean;
  issuer: string;
  /** Pinned in production so token audiences never follow a request Host header. */
  canonicalApiOrigin: () => string | null;
  jwks: JwksSource;
  records: NativeProductRecordsPort;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
  now: () => Date;
  createId: () => string;
};

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'Authorization, Content-Type, Mcp-Protocol-Version',
  'access-control-expose-headers': 'WWW-Authenticate',
};

function respond(result: McpHttpResult) {
  const headers = { ...CORS, 'cache-control': 'no-store', ...result.headers };
  return result.body === null
    ? new NextResponse(null, { status: result.status, headers })
    : NextResponse.json(result.body, { status: result.status, headers });
}

const notFound = () =>
  new NextResponse(null, { status: 404, headers: { 'cache-control': 'no-store' } });

export function createMcpRouteHandlers(dependencies: McpRouteDependencies) {
  const resourceFor = (request: Request) =>
    mcpResourceUrl(new URL(request.url).origin, dependencies.canonicalApiOrigin());

  return {
    async post(request: Request) {
      if (!dependencies.enabled()) return notFound();
      const resourceUrl = resourceFor(request);
      const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
      if (!token) return respond(unauthenticatedResult(resourceUrl));
      const principal = await verifyAccessToken(token, {
        issuer: dependencies.issuer,
        audience: resourceUrl,
        jwks: dependencies.jwks,
        nowSeconds: Math.floor(dependencies.now().getTime() / 1000),
      });
      if (!principal) return respond(unauthenticatedResult(resourceUrl, 'invalid_token'));
      const body: unknown = await request.json().catch(() => null);
      return respond(
        await handleMcpRequest({
          body,
          principal,
          deps: {
            resourceUrl,
            records: dependencies.records,
            reserveRequest: dependencies.reserveRequest,
            now: dependencies.now,
            createId: dependencies.createId,
          },
        }),
      );
    },

    /** Stateless server: no SSE stream to resume. */
    get() {
      if (!dependencies.enabled()) return notFound();
      return new NextResponse(null, { status: 405, headers: { ...CORS, allow: 'POST, OPTIONS' } });
    },

    options() {
      return new NextResponse(null, { status: 204, headers: CORS });
    },

    metadata(request: Request) {
      if (!dependencies.enabled()) return notFound();
      return NextResponse.json(
        protectedResourceMetadata({
          resourceUrl: resourceFor(request),
          issuer: dependencies.issuer,
        }),
        { headers: { ...CORS, 'cache-control': 'no-store' } },
      );
    },
  };
}
