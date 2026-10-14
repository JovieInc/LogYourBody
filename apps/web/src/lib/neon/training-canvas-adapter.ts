import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { canvasLedgerSchema, type CanvasLedgerPort } from '@/lib/training/mesocycle-canvas';
import {
  NativeAccountAdmissionError,
  type NativeAccountAdmission,
  type NativeAccountAdmissionPort,
} from '@/lib/ports/native-account-admission';
import {
  captureNativeAccountAdmission,
  executeNativeMutationQueries,
} from './native-account-admission';

function database() {
  const url = process.env.DATABASE_URL || process.env.WAITLIST_DATABASE_URL;
  if (!url) throw new Error('Missing DATABASE_URL for the mesocycle canvas');
  return neon(url);
}

export function createNeonCanvasLedger(
  admission: NativeAccountAdmission,
  sql: NeonQueryFunction<false, false> = database(),
): CanvasLedgerPort {
  function assertSubject(subject: string) {
    if (subject !== admission.subject) throw new NativeAccountAdmissionError('account_changed');
  }
  return {
    async load(subject) {
      assertSubject(subject);
      const [rows] = await executeNativeMutationQueries(sql, admission, [
        sql.query('select public.training_canvas_load($1) as payload', [subject]),
      ]);
      if (!rows[0]?.payload) return null;
      const parsed = canvasLedgerSchema.safeParse(rows[0].payload);
      if (!parsed.success) throw new Error('canvas_ledger_invalid');
      return parsed.data;
    },
    async save(subject, expectedWrite, ledger) {
      assertSubject(subject);
      const [rows] = await executeNativeMutationQueries(sql, admission, [
        sql.query('select public.training_canvas_save($1,$2::uuid,$3,$4::jsonb) as result', [
          subject,
          admission.ownerId,
          expectedWrite,
          JSON.stringify(ledger),
        ]),
      ]);
      const kind = (rows[0]?.result as { kind?: string } | undefined)?.kind;
      if (kind === 'saved') return { kind: 'saved' };
      if (kind === 'stale' || kind === 'owner_missing') return { kind: 'stale' };
      return { kind: 'missed_update' };
    },
  };
}

export const neonCanvasAccounts: NativeAccountAdmissionPort = {
  capture: (subject) => captureNativeAccountAdmission(database(), subject),
};
