import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import type { ProductUserRecord } from '@/lib/ports/user-directory';

const CURRENT_TERMS_VERSION = '2026-07-14';
const CURRENT_PRIVACY_VERSION = '2026-07-14';

const ProfileUpdateSchema = z
  .object({
    fullName: z.string().trim().min(1).max(120).optional(),
    dateOfBirth: z.string().date().optional(),
    height: z.number().min(50).max(275).optional(),
    heightUnit: z.enum(['cm', 'in']).optional(),
    gender: z.string().trim().min(1).max(40).optional(),
    activityLevel: z.string().trim().min(1).max(40).optional(),
    goalWeight: z.number().positive().max(1_000).optional(),
    goalWeightUnit: z.enum(['kg', 'lb']).optional(),
    onboardingCompleted: z.boolean().optional(),
    legalAccepted: z.literal(true).optional(),
  })
  .strict();

async function authenticate(request: NextRequest) {
  const accessToken = request.headers.get('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) return null;
  return fetchUserInfo(accessToken);
}

function publicProfile(user: ProductUserRecord) {
  const profile = user.profileData;
  return {
    id: user.subject,
    email: user.email,
    username: null,
    full_name: profile.full_name || user.displayName,
    date_of_birth: profile.date_of_birth || null,
    height: profile.height || null,
    height_unit: profile.height_unit || null,
    gender: profile.gender || null,
    activity_level: profile.activity_level || null,
    goal_weight: profile.goal_weight || null,
    goal_weight_unit: profile.goal_weight_unit || null,
    onboarding_completed: Boolean(user.onboardingCompletedAt),
    legal_accepted_at: user.legalAcceptedAt?.toISOString() || null,
  };
}

export async function GET(request: NextRequest) {
  const identity = await authenticate(request);
  if (!identity) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const user = await neonUserDirectory.getUser(identity.sub);
  if (!user) return NextResponse.json({ error: 'not_found' }, { status: 404 });
  return NextResponse.json(
    { profile: publicProfile(user) },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function PATCH(request: NextRequest) {
  const identity = await authenticate(request);
  if (!identity) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const parsed = ProfileUpdateSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'invalid_profile' }, { status: 400 });
  }

  const input = parsed.data;
  const profileData: Record<string, unknown> = {};
  if (input.fullName !== undefined) profileData.full_name = input.fullName;
  if (input.dateOfBirth !== undefined) profileData.date_of_birth = input.dateOfBirth;
  if (input.height !== undefined) profileData.height = input.height;
  if (input.heightUnit !== undefined) profileData.height_unit = input.heightUnit;
  if (input.gender !== undefined) profileData.gender = input.gender;
  if (input.activityLevel !== undefined) profileData.activity_level = input.activityLevel;
  if (input.goalWeight !== undefined) profileData.goal_weight = input.goalWeight;
  if (input.goalWeightUnit !== undefined) profileData.goal_weight_unit = input.goalWeightUnit;
  if (input.onboardingCompleted !== undefined) {
    profileData.onboarding_completed = input.onboardingCompleted;
  }

  const user = await neonUserDirectory.updateProfile(identity.sub, {
    profileData,
    displayName: input.fullName,
    onboardingCompleted: input.onboardingCompleted,
    acceptLegal: input.legalAccepted,
    termsVersion: input.legalAccepted ? CURRENT_TERMS_VERSION : undefined,
    privacyVersion: input.legalAccepted ? CURRENT_PRIVACY_VERSION : undefined,
  });
  return NextResponse.json(
    { profile: publicProfile(user) },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function DELETE(request: NextRequest) {
  const identity = await authenticate(request);
  if (!identity) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  await neonUserDirectory.deleteUser(identity.sub);
  return new NextResponse(null, { status: 204 });
}
