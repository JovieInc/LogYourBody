import type { UserProfile } from '@/types/body-metrics';

function toUserProfile(value: Record<string, unknown>): UserProfile {
  return {
    id: String(value.id || ''),
    email: typeof value.email === 'string' ? value.email : '',
    full_name: typeof value.full_name === 'string' ? value.full_name : undefined,
    first_name: typeof value.first_name === 'string' ? value.first_name : null,
    last_name: typeof value.last_name === 'string' ? value.last_name : null,
    date_of_birth: typeof value.date_of_birth === 'string' ? value.date_of_birth : undefined,
    height: typeof value.height === 'number' ? value.height : undefined,
    height_unit:
      value.height_unit === 'cm' || value.height_unit === 'ft' ? value.height_unit : undefined,
    gender: value.gender === 'female' || value.gender === 'male' ? value.gender : undefined,
    activity_level:
      typeof value.activity_level === 'string'
        ? (value.activity_level as UserProfile['activity_level'])
        : undefined,
    goal_weight: typeof value.goal_weight === 'number' ? value.goal_weight : undefined,
    goal_weight_unit:
      value.goal_weight_unit === 'kg' || value.goal_weight_unit === 'lbs'
        ? value.goal_weight_unit
        : undefined,
    email_verified: Boolean(value.email_verified),
    onboarding_completed: Boolean(value.onboarding_completed),
    settings: {},
    created_at: typeof value.created_at === 'string' ? value.created_at : '',
    updated_at: typeof value.updated_at === 'string' ? value.updated_at : '',
  };
}

async function requestProfile(input: RequestInit = {}): Promise<UserProfile | null> {
  const response = await fetch('/api/profile', { ...input, cache: 'no-store' });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error('Unable to load profile');
  const payload = (await response.json()) as { profile?: Record<string, unknown> };
  return payload.profile ? toUserProfile(payload.profile) : null;
}

export function getProfile(_userId: string) {
  return requestProfile();
}

export function updateProfile(_userId: string, updates: Partial<UserProfile>) {
  const { id, created_at, updated_at, settings, ...profile } = updates;
  void id;
  void created_at;
  void updated_at;
  void settings;
  return requestProfile({
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      fullName: profile.full_name,
      dateOfBirth: profile.date_of_birth,
      height: profile.height,
      heightUnit: profile.height_unit === 'ft' ? 'in' : profile.height_unit,
      gender: profile.gender,
      activityLevel: profile.activity_level,
      goalWeight: profile.goal_weight,
      goalWeightUnit: profile.goal_weight_unit,
      onboardingCompleted: profile.onboarding_completed,
    }),
  });
}
