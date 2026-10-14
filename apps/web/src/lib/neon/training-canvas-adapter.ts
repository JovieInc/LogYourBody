import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { canvasLedgerSchema, type CanvasLedgerPort } from '@/lib/training/mesocycle-canvas';

function database() {
  const url = process.env.DATABASE_URL || process.env.WAITLIST_DATABASE_URL;
  if (!url) throw new Error('Missing DATABASE_URL for the mesocycle canvas');
  return neon(url);
}

export function createNeonCanvasLedger(
  sql: NeonQueryFunction<false, false> = database(),
): CanvasLedgerPort {
  return {
    async load(subject) {
      const rows = (await sql.query('select public.training_canvas_load($1) as payload', [
        subject,
      ])) as Array<{ payload: unknown }>;
      if (!rows[0]?.payload) return null;
      const parsed = canvasLedgerSchema.safeParse(rows[0].payload);
      if (!parsed.success) throw new Error('canvas_ledger_invalid');
      return parsed.data;
    },
    async save(subject, expectedWrite, ledger) {
      const rows = (await sql.query(
        'select public.training_canvas_save($1,$2,$3::jsonb) as result',
        [subject, expectedWrite, JSON.stringify(ledger)],
      )) as Array<{ result: { kind?: string } }>;
      const kind = rows[0]?.result?.kind;
      if (kind === 'saved') return { kind: 'saved' };
      if (kind === 'stale' || kind === 'owner_missing') return { kind: 'stale' };
      return { kind: 'missed_update' };
    },
  };
}

export const neonCanvasLedger: CanvasLedgerPort = {
  load: (subject) => createNeonCanvasLedger().load(subject),
  save: (subject, expectedWrite, ledger) =>
    createNeonCanvasLedger().save(subject, expectedWrite, ledger),
};
