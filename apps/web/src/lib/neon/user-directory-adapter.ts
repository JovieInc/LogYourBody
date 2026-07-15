import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type { ProductUserRecord, UserDirectoryPort } from '@/lib/ports/user-directory';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL || process.env.WAITLIST_DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

type AppUserRow = {
  identity_subject: string;
  phone_e164: string | null;
  email: string | null;
  display_name: string | null;
  avatar_url: string | null;
  profile_data: Record<string, unknown> | null;
  onboarding_completed_at: Date | string | null;
  legal_accepted_at: Date | string | null;
  terms_version: string | null;
  privacy_version: string | null;
};

function toDate(value: Date | string | null): Date | null {
  if (!value) return null;
  return value instanceof Date ? value : new Date(value);
}

function mapUser(row: AppUserRow): ProductUserRecord {
  return {
    subject: row.identity_subject,
    phoneNumber: row.phone_e164,
    email: row.email,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    profileData: row.profile_data || {},
    onboardingCompletedAt: toDate(row.onboarding_completed_at),
    legalAcceptedAt: toDate(row.legal_accepted_at),
    termsVersion: row.terms_version,
    privacyVersion: row.privacy_version,
  };
}

const userColumns = `
  identity_subject,
  phone_e164,
  email,
  display_name,
  avatar_url,
  profile_data,
  onboarding_completed_at,
  legal_accepted_at,
  terms_version,
  privacy_version
`;

export const neonUserDirectory: UserDirectoryPort = {
  async recordSignIn(identity) {
    await getDatabase()`
      insert into public.app_users (
        identity_provider,
        identity_subject,
        phone_e164,
        email,
        display_name,
        avatar_url,
        last_signed_in_at
      ) values (
        'jovie',
        ${identity.subject},
        ${identity.phoneNumber || null},
        ${identity.email || null},
        ${identity.displayName || null},
        ${identity.avatarUrl || null},
        now()
      )
      on conflict (identity_provider, identity_subject) do update set
        phone_e164 = coalesce(excluded.phone_e164, app_users.phone_e164),
        email = coalesce(excluded.email, app_users.email),
        display_name = coalesce(excluded.display_name, app_users.display_name),
        avatar_url = coalesce(excluded.avatar_url, app_users.avatar_url),
        last_signed_in_at = now(),
        updated_at = now()
    `;
  },

  async getUser(subject) {
    const rows = (await getDatabase().query(
      `select ${userColumns}
       from public.app_users
       where identity_provider = 'jovie' and identity_subject = $1
       limit 1`,
      [subject],
    )) as AppUserRow[];
    return rows[0] ? mapUser(rows[0]) : null;
  },

  async updateProfile(subject, update) {
    const rows = (await getDatabase().query(
      `update public.app_users
       set profile_data = profile_data || $2::jsonb,
           display_name = coalesce($3, display_name),
           onboarding_completed_at = case
             when $4::boolean then coalesce(onboarding_completed_at, now())
             else onboarding_completed_at
           end,
           legal_accepted_at = case
             when $5::boolean then coalesce(legal_accepted_at, now())
             else legal_accepted_at
           end,
           terms_version = case when $5::boolean then $6 else terms_version end,
           privacy_version = case when $5::boolean then $7 else privacy_version end,
           updated_at = now()
       where identity_provider = 'jovie' and identity_subject = $1
       returning ${userColumns}`,
      [
        subject,
        JSON.stringify(update.profileData),
        update.displayName || null,
        update.onboardingCompleted === true,
        update.acceptLegal === true,
        update.termsVersion || null,
        update.privacyVersion || null,
      ],
    )) as AppUserRow[];
    if (!rows[0]) throw new Error('Product user does not exist');
    return mapUser(rows[0]);
  },

  async deleteUser(subject) {
    await getDatabase()`
      delete from public.app_users
      where identity_provider = 'jovie' and identity_subject = ${subject}
    `;
  },
};
