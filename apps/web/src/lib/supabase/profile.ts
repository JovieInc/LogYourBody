// Compatibility export for older call sites while the web data-plane cutover completes.
// The implementation is server-backed through the Jovie session and Neon; this module must
// not grow a Supabase dependency again.
export { getProfile, updateProfile } from '@/lib/profile';
