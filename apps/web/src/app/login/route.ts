import { redirect } from 'next/navigation';

// Retain legacy auth destinations used by OAuth error callbacks and bookmarks.
export function GET() {
  redirect('/');
}
