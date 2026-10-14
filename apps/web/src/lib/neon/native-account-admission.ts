import 'server-only';
import type { NeonQueryFunction, NeonQueryPromise } from '@neondatabase/serverless';
import {
  NativeAccountAdmissionError,
  type NativeAccountAdmission,
} from '@/lib/ports/native-account-admission';

type Database = NeonQueryFunction<false, false>;
export type NativeMutationQuery = NeonQueryPromise<false, false, Record<string, unknown>[]>;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function captureNativeAccountAdmission(
  database: Database,
  subject: string,
): Promise<NativeAccountAdmission | null> {
  const rows = await database.query(
    `select id from public.app_users
     where identity_provider = 'jovie' and identity_subject = $1`,
    [subject],
  );
  const ownerId = rows[0]?.id;
  if (!ownerId) return null;
  if (typeof ownerId !== 'string' || !UUID.test(ownerId)) {
    throw new NativeAccountAdmissionError('account_admission_unavailable');
  }
  return Object.freeze({ subject, ownerId });
}

export function nativeAccountGuard(database: Database, admission: NativeAccountAdmission) {
  if (!admission || !admission.subject?.trim() || !UUID.test(admission.ownerId ?? '')) {
    throw new NativeAccountAdmissionError('account_changed');
  }
  return database.query('select public.lyb_native_account_admit($1, $2::uuid)', [
    admission.subject,
    admission.ownerId,
  ]);
}

export async function executeNativeMutationQueries(
  database: Database,
  admission: NativeAccountAdmission | undefined,
  queries: NativeMutationQuery[],
): Promise<Array<Record<string, unknown>[]>> {
  if (!admission) {
    // Retained internal storage behavior. Public native handlers exclusively use
    // the explicit admitted capability below; they never fall back to this path.
    const results = [];
    for (const query of queries) results.push(await query);
    return results;
  }
  try {
    const results = await database.transaction([
      nativeAccountGuard(database, admission),
      ...queries,
    ]);
    return results.slice(1);
  } catch (error) {
    if (error instanceof NativeAccountAdmissionError) throw error;
    const code = (error as { code?: string } | null)?.code;
    if (code === 'LYB01') throw new NativeAccountAdmissionError('account_changed');
    if (code === '42883') throw new NativeAccountAdmissionError('account_admission_unavailable');
    throw error;
  }
}
