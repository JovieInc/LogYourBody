import { NextResponse } from 'next/server';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';

export async function DELETE() {
  try {
    const { userId } = await getServerAuthSession();
    if (!userId) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    await neonUserDirectory.deleteUser(userId);
    return NextResponse.json({ message: 'Account deleted successfully' }, { status: 200 });
  } catch (error) {
    console.error('Delete account error:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
