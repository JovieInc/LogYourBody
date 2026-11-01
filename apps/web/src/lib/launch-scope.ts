/** Exact paths the launch inventory hides or deletes. Checked before auth so a tombstone is not a sign-in dead end. */
const EXACT_REDIRECTS: Record<string, string> = {
  '/about': '/',
  '/blog': '/',
  '/brand': '/',
  '/careers': '/',
  '/changelog': '/',
  '/dashboard': '/',
  '/download/android': '/download/ios',
  '/import': '/',
  '/log': '/',
  '/onboarding': '/',
  '/photos': '/',
  '/preferences': '/',
  '/profile': '/',
  '/settings/notifications': '/',
  '/settings/preferences': '/',
  '/settings/profile': '/',
  '/steps': '/',
  '/training/canvas': '/',
};

export function launchScopeRedirect(pathname: string): string | null {
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  if (EXACT_REDIRECTS[path]) return EXACT_REDIRECTS[path];
  if (path.startsWith('/blog/')) return '/';
  if (path.startsWith('/training/canvas/')) return '/';
  return null;
}
