import 'server-only';
import { Statsig, StatsigUser } from '@statsig/statsig-node-core';

let client: Statsig | null = null;
let initialized = false;
let initializing: Promise<boolean> | null = null;

async function initialize(): Promise<boolean> {
  if (initialized) return true;
  if (initializing) return initializing;
  const key = process.env.STATSIG_SERVER_API_KEY;
  if (!key) return false;

  initializing = (async () => {
    let candidate: Statsig | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      candidate = new Statsig(key, {
        environment:
          process.env.NEXT_PUBLIC_STATSIG_ENV_TIER ||
          (process.env.VERCEL_ENV === 'production' ? 'production' : 'development'),
        initTimeoutMs: 500,
        disableCountryLookup: true,
        outputLogLevel: 'none',
      });
      const result = await Promise.race([
        candidate.initialize(),
        new Promise<{ isSuccess: boolean }>((resolve) => {
          timer = setTimeout(() => resolve({ isSuccess: false }), 750);
        }),
      ]);
      if (result.isSuccess) {
        client = candidate;
        initialized = true;
        return true;
      }
      return false;
    } catch {
      return false;
    } finally {
      clearTimeout(timer);
      if (!initialized && candidate) {
        const failed = candidate;
        void Promise.resolve()
          .then(() => failed.shutdown(250))
          .catch(() => {});
      }
    }
  })();

  try {
    return await initializing;
  } finally {
    initializing = null;
  }
}

/** A global public launch switch, not a visitor experiment or analytics identity. */
export async function readPublicLandingGate(gateName: string): Promise<boolean> {
  if (!(await initialize()) || !client) return false;
  try {
    const gate = client.getFeatureGate(StatsigUser.withUserID('lyb-public-homepage'), gateName);
    return gate.getEvaluationDetails().reason !== 'Unrecognized' && gate.value === true;
  } catch {
    return false;
  }
}
