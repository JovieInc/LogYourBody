import { NextRequest, NextResponse } from 'next/server';
import { datedOutcomeEditSchema, type DatedOutcomePort } from '@/lib/ports/dated-outcome';
import {
  NativeAccountAdmissionError,
  nativeAccountFailureStatus,
  requireNativeAccountAdmission,
} from '@/lib/ports/native-account-admission';

export function createDatedOutcomeHandlers(deps: {
  authenticate: (request: NextRequest) => Promise<{ sub: string } | null>;
  outcomes: DatedOutcomePort;
  enabled: () => boolean;
}) {
  function json(body: unknown, status = 200) {
    return NextResponse.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
  }
  async function handle(request: NextRequest, write: boolean) {
    const identity = await deps.authenticate(request);
    if (!identity) return json({ error: 'unauthorized' }, 401);
    // Default-off server admission complements the native Platform gate.
    if (!deps.enabled()) return json({ error: 'dated_outcome_unavailable' }, 404);
    try {
      if (!write) return json({ snapshot: await deps.outcomes.read(identity.sub) });
      const admission = requireNativeAccountAdmission(await deps.outcomes.capture(identity.sub));
      const parsed = datedOutcomeEditSchema.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return json({ error: 'invalid_dated_outcome' }, 400);
      const result = await deps.outcomes.save(admission, parsed.data);
      return result.kind === 'saved' ? json(result) : json({ error: result.kind }, 409);
    } catch (error) {
      const status = nativeAccountFailureStatus(error);
      if (status !== null)
        return json({ error: (error as NativeAccountAdmissionError).code }, status);
      throw error;
    }
  }
  return {
    GET: (request: NextRequest) => handle(request, false),
    PUT: (request: NextRequest) => handle(request, true),
  };
}
