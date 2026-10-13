import {
  NativeAccountAdmissionError,
  nativeAccountFailureStatus,
} from '@/lib/ports/native-account-admission';
import { NextResponse } from 'next/server';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';

export async function DELETE() {
  try {
    const { userId } = await getServerAuthSession();
    if (!userId) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    const admission = await neonUserDirectory.captureAccountAdmission(userId);
    if (admission) await neonUserDirectory.deleteUser(admission);
    return NextResponse.json({ message: 'Account deleted successfully' }, { status: 200 });
  } catch (error) {
    const status = nativeAccountFailureStatus(error);
    if (status !== null)
      return NextResponse.json({ error: (error as NativeAccountAdmissionError).code }, { status });
    console.error('Delete account error:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
