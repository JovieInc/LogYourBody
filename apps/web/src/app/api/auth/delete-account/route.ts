import { NextResponse } from 'next/server';
import { auth, clerkClient } from '@clerk/nextjs/server';
import { createClerkSupabaseClient } from '@/lib/supabase/clerk-client';

type DeleteTarget = {
  table: string;
  column: string;
};

const deleteTargets: DeleteTarget[] = [
  { table: 'progress_photos', column: 'user_id' },
  { table: 'daily_metrics', column: 'user_id' },
  { table: 'body_metrics', column: 'user_id' },
  { table: 'user_goals', column: 'user_id' },
  { table: 'profiles', column: 'id' },
];

function describeDeletionError(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === 'object' && error !== null) {
    const record = error as Record<string, unknown>;
    const message = record.message ?? record.details ?? record.code;

    if (typeof message === 'string' && message.length > 0) {
      return message;
    }
  }

  return String(error);
}

function cleanupFailureResponse() {
  return NextResponse.json(
    { error: 'Unable to delete all account data. Please try again or contact support.' },
    { status: 502 },
  );
}

export async function DELETE() {
  try {
    const { userId, getToken } = await auth();

    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const token = await getToken();

    if (!token) {
      return NextResponse.json({ error: 'Missing authentication token' }, { status: 401 });
    }

    const supabase = await createClerkSupabaseClient(() => Promise.resolve(token));

    try {
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

      if (!supabaseUrl || !supabaseAnonKey) {
        console.error('Missing Supabase environment variables for delete-user-assets function');
        return cleanupFailureResponse();
      } else {
        const response = await fetch(`${supabaseUrl}/functions/v1/delete-user-assets`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: supabaseAnonKey,
            Authorization: `Bearer ${token}`,
          },
        });

        if (!response.ok) {
          const text = await response.text().catch(() => '');
          console.error('delete-user-assets function failed', {
            status: response.status,
            body: text,
          });

          return cleanupFailureResponse();
        }
      }
    } catch (error) {
      console.error('Error calling delete-user-assets function', error);
      return cleanupFailureResponse();
    }

    for (const target of deleteTargets) {
      const { error } = await supabase.from(target.table).delete().eq(target.column, userId);

      if (error) {
        console.error('Failed to delete account data before Clerk user deletion', {
          table: target.table,
          column: target.column,
          error: describeDeletionError(error),
        });

        return cleanupFailureResponse();
      }
    }

    const client = await clerkClient();
    await client.users.deleteUser(userId);

    return NextResponse.json({ message: 'Account deleted successfully' }, { status: 200 });
  } catch (error) {
    console.error('Delete account error:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
