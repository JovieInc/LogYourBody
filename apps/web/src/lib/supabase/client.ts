import { createBrowserClient } from '@supabase/ssr';

export const SUPABASE_DATA_PLANE_RETIRED =
  'Supabase data plane retired. LogYourBody product data is stored in Neon behind first-party APIs.';

export function createClient(): ReturnType<typeof createBrowserClient> {
  throw new Error(SUPABASE_DATA_PLANE_RETIRED);
}

export const supabase = new Proxy({} as ReturnType<typeof createBrowserClient>, {
  get() {
    throw new Error(SUPABASE_DATA_PLANE_RETIRED);
  },
});
