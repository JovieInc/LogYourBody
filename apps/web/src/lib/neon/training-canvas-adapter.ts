import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { parseJournal, type CanvasPort } from '@/lib/training/mesocycle-canvas';

function database() {
  const url = process.env.DATABASE_URL || process.env.WAITLIST_DATABASE_URL;
  if (!url) throw new Error('Missing DATABASE_URL for mesocycle canvas');
  return neon(url);
}

/** Neon compare-and-swap for the canvas journal. A missing function throws; callers return 503. */
export function createNeonCanvasPort(
  sql: NeonQueryFunction<false, false> = database(),
): CanvasPort {
  return {
    async read(subject) {
      const rows = (await sql.query('select public.training_canvas_read($1) as document', [
        subject,
      ])) as Array<{ document: unknown }>;
      const document = rows[0]?.document;
      if (document == null) return null;
      const parsed = parseJournal(document);
      if (!parsed) throw new Error('training_canvas_corrupt');
      return parsed;
    },
    async write(subject, expectedGeneration, journal) {
      const rows = (await sql.query(
        'select public.training_canvas_write($1,$2,$3::jsonb) as result',
        [subject, expectedGeneration, JSON.stringify(journal)],
      )) as Array<{ result?: { kind?: string } }>;
      const kind = rows[0]?.result?.kind;
      if (kind === 'ok' || kind === 'conflict' || kind === 'owner_missing') return kind;
      throw new Error('training_canvas_unavailable');
    },
  };
}
