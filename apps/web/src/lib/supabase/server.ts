const SUPABASE_DATA_PLANE_RETIRED =
  'Supabase data plane retired. LogYourBody product data is stored in Neon behind first-party APIs.';

export async function createClient(): Promise<never> {
  throw new Error(SUPABASE_DATA_PLANE_RETIRED);
}
