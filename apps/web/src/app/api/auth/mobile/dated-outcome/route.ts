import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonDatedOutcomes } from '@/lib/neon/dated-outcome-adapter';
import { createDatedOutcomeHandlers } from './route-handlers';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const handlers = createDatedOutcomeHandlers({
  authenticate: async (request) => {
    const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
    return token ? fetchUserInfo(token) : null;
  },
  outcomes: {
    capture: (subject) => neonDatedOutcomes().capture(subject),
    read: (subject) => neonDatedOutcomes().read(subject),
    save: (admission, edit) => neonDatedOutcomes().save(admission, edit),
  },
  enabled: () => process.env.LYB_DATED_OUTCOME_ENABLED === 'true',
});
export const GET = handlers.GET;
export const PUT = handlers.PUT;
