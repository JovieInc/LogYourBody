import { NextResponse } from 'next/server';
import { LYB_MCP_SCOPES } from '@/lib/mcp/contract';
import {
  correctWeightEntry,
  createWeightEntry,
  deleteWeightEntry,
  listWeightEntries,
  type WeightActionResult,
  type WeightFailure,
  type WeightLifecyclePort,
} from '@/lib/metrics/weight-lifecycle';

export type WeightPrincipal = { subject: string; scopes: ReadonlySet<string> };

export type WeightRouteDependencies = {
  enabled: () => boolean;
  authenticate: (request: Request) => Promise<WeightPrincipal | null>;
  store: WeightLifecyclePort;
  now: () => Date;
};

const hidden = () =>
  new NextResponse(null, { status: 404, headers: { 'cache-control': 'no-store' } });

function json(body: unknown, status: number) {
  return NextResponse.json(body, { status, headers: { 'cache-control': 'no-store' } });
}

function failureStatus(failure: WeightFailure): number {
  switch (failure.code) {
    case 'invalid_input':
      return 400;
    case 'spoofed_subject':
    case 'revoked':
    case 'account_deleted':
    case 'unconnected':
    case 'consent_required':
    case 'ineligible':
      return 403;
    case 'gate_off':
    case 'not_found':
    case 'account_not_found':
      return 404;
    default:
      return 409;
  }
}

function failureBody(failure: WeightFailure) {
  if (failure.code === 'gate_off') return null;
  if (failure.code === 'invalid_input')
    return { error: failure.code, reason: failure.reason ?? 'rejected_shape' };
  return { error: failure.code };
}

async function authorized(
  request: Request,
  deps: WeightRouteDependencies,
  scope: string,
): Promise<WeightPrincipal | NextResponse> {
  if (!deps.enabled()) return hidden();
  const principal = await deps.authenticate(request);
  if (!principal) return json({ error: 'unauthorized' }, 401);
  if (!principal.scopes.has(scope)) return json({ error: 'insufficient_scope' }, 403);
  return principal;
}

function actionResponse(result: WeightActionResult) {
  if (!result.ok) {
    const body = failureBody(result);
    return body ? json(body, failureStatus(result)) : hidden();
  }
  return json({ replayed: result.replayed, receipt: result.receipt }, 200);
}

export function createWeightRouteHandlers(deps: WeightRouteDependencies) {
  return {
    async post(request: Request) {
      const principal = await authorized(request, deps, LYB_MCP_SCOPES.metricsWrite);
      if (principal instanceof NextResponse) return principal;
      const body: unknown = await request.json().catch(() => null);
      return actionResponse(
        await createWeightEntry({
          gateEnabled: true,
          subject: principal.subject,
          body,
          store: deps.store,
          now: deps.now(),
        }),
      );
    },

    async get(request: Request) {
      const principal = await authorized(request, deps, LYB_MCP_SCOPES.metricsRead);
      if (principal instanceof NextResponse) return principal;
      const url = new URL(request.url);
      const limitRaw = url.searchParams.get('limit');
      const listed = await listWeightEntries({
        gateEnabled: true,
        subject: principal.subject,
        store: deps.store,
        query: {
          cursor: url.searchParams.get('cursor') ?? undefined,
          limit: limitRaw === null ? undefined : Number(limitRaw),
          record_id: url.searchParams.get('record_id') ?? undefined,
          subject: url.searchParams.get('subject') ?? undefined,
          user_id: url.searchParams.get('user_id') ?? undefined,
        },
      });
      if (!listed.ok) return actionResponse(listed);
      return json({ records: listed.records, next_cursor: listed.next_cursor }, 200);
    },

    async correct(request: Request) {
      const principal = await authorized(request, deps, LYB_MCP_SCOPES.metricsWrite);
      if (principal instanceof NextResponse) return principal;
      const body: unknown = await request.json().catch(() => null);
      return actionResponse(
        await correctWeightEntry({
          gateEnabled: true,
          subject: principal.subject,
          body,
          store: deps.store,
          now: deps.now(),
        }),
      );
    },

    async remove(request: Request) {
      const principal = await authorized(request, deps, LYB_MCP_SCOPES.metricsWrite);
      if (principal instanceof NextResponse) return principal;
      const body: unknown = await request.json().catch(() => null);
      return actionResponse(
        await deleteWeightEntry({
          gateEnabled: true,
          subject: principal.subject,
          body,
          store: deps.store,
          now: deps.now(),
        }),
      );
    },
  };
}
