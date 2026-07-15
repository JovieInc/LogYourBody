import { NextResponse } from 'next/server';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';

function cleanupFailureResponse() {
  return NextResponse.json(
    { error: 'Unable to delete all account data. Please try again or contact support.' },
    { status: 502 },
  );
}

export async function DELETE() {
  try {
    const { userId, getToken } = await getServerAuthSession();
    if (!userId) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    const token = await getToken();
    if (!token)
      return NextResponse.json({ error: 'Missing authentication token' }, { status: 401 });

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!supabaseUrl || !supabaseAnonKey) return cleanupFailureResponse();

    const response = await fetch(`${supabaseUrl}/functions/v1/delete-user-assets`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok) return cleanupFailureResponse();
    return NextResponse.json({ message: 'Account deleted successfully' }, { status: 200 });
  } catch (error) {
    console.error('Delete account error:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
