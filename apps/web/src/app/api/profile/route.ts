import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { authCookies, fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import type { ProductUserRecord } from '@/lib/ports/user-directory';

const ProfileUpdateSchema = z
  .object({
    fullName: z.string().trim().min(1).max(120).optional(),
    dateOfBirth: z.string().date().optional(),
    height: z.number().min(50).max(275).optional(),
    heightUnit: z.enum(['cm', 'in']).optional(),
    gender: z.enum(['male', 'female']).optional(),
    activityLevel: z.string().trim().min(1).max(40).optional(),
    goalWeight: z.number().positive().max(1000).optional(),
    goalWeightUnit: z.enum(['kg', 'lbs']).optional(),
    onboardingCompleted: z.boolean().optional(),
  })
  .strict();

async function currentUser(request: NextRequest) {
  const token = request.cookies.get(authCookies.accessToken)?.value;
  return token ? fetchUserInfo(token) : null;
}

function serializeProfile(user: ProductUserRecord) {
  const profile = user.profileData;
  return {
    id: user.subject,
    email: user.email,
    full_name: profile.full_name || user.displayName || null,
    date_of_birth: profile.date_of_birth || null,
    height: profile.height || null,
    height_unit: profile.height_unit === 'in' ? 'ft' : profile.height_unit || null,
    gender: profile.gender || null,
    activity_level: profile.activity_level || null,
    goal_weight: profile.goal_weight || null,
    goal_weight_unit: profile.goal_weight_unit || null,
    email_verified: true,
    onboarding_completed: Boolean(user.onboardingCompletedAt),
    created_at: null,
    updated_at: null,
  };
}

export async function GET(request: NextRequest) {
  const identity = await currentUser(request);
  if (!identity) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const user = await neonUserDirectory.getUser(identity.sub);
  if (!user) return NextResponse.json({ error: 'Profile not found' }, { status: 404 });
  return NextResponse.json(
    { profile: serializeProfile(user) },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function PATCH(request: NextRequest) {
  const identity = await currentUser(request);
  if (!identity) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const parsed = ProfileUpdateSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: 'Invalid profile' }, { status: 400 });

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

  const user = await neonUserDirectory.updateProfile(identity.sub, {
    profileData,
    displayName: input.fullName,
    onboardingCompleted: input.onboardingCompleted,
  });
  return NextResponse.json(
    { profile: serializeProfile(user) },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
