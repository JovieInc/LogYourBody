import { NextRequest, NextResponse } from 'next/server';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';

export async function POST(request: NextRequest) {
  const authorization = request.headers.get('authorization');
  const accessToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const user = await fetchUserInfo(accessToken);
  if (!user) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  await neonUserDirectory.recordSignIn({
    subject: user.sub,
    phoneNumber: user.phone_number,
    email: user.email,
    displayName: user.name,
    avatarUrl: user.picture,
  });
  return NextResponse.json(
    { user: { id: user.sub } },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
