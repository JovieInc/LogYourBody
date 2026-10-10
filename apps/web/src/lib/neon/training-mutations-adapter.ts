import 'server-only';
import { z } from 'zod';
import type { NeonQueryFunction } from '@neondatabase/serverless';
import type { TrainingMutationsPort } from '@/lib/ports/training-mutations';
import { isProgramSetup } from '@/lib/training/engine';

const contextSchema = z.object({
  ownerId: z.string().uuid(),
  generation: z.number().int().nonnegative().safe(),
  headRevision: z.string().uuid().nullable(),
  legacySetups: z.array(z.unknown()),
});
const recordSchema = z
  .object({
    id: z.string().uuid(),
    user_id: z.string(),
    deleted_at: z.null(),
    server_updated_at: z.string(),
  })
  .passthrough();
const conflictSchema = z.enum([
  'owner_missing',
  'stale_admission',
  'session_conflict',
  'record_conflict',
]);
export function createNeonTrainingMutations(
  sql: NeonQueryFunction<false, false>,
): TrainingMutationsPort {
  return {
    async captureAdmission(subject) {
      const rows = (await sql.query('select public.training_revision_context($1) as context', [
        subject,
      ])) as Array<{ context: unknown }>;
      if (!rows[0]?.context) return null;
      const context = contextSchema.parse(rows[0].context);
      const setup = context.legacySetups
        .filter(isProgramSetup)
        .sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt))[0];
      if (!setup) return null;
      if ((setup.programRevisionId ?? null) !== context.headRevision)
        throw new Error('training_revision_mismatch');
      return {
        ownerId: context.ownerId,
        generation: context.generation,
        setupId: setup.id,
        revisionId: setup.programRevisionId ?? null,
      };
    },
    async commit(input) {
      const rows = (await sql.query(
        'select public.training_mutation_command($1,$2,$3::jsonb,$4::jsonb) as result',
        [
          input.subject,
          input.action,
          JSON.stringify(input.admission),
          JSON.stringify(input.record),
        ],
      )) as Array<{ result: Record<string, unknown> }>;
      const result = rows[0]?.result;
      if (!result) throw new Error('training_mutation_unavailable');
      if (result.kind !== 'saved') return { kind: conflictSchema.parse(result.kind) };
      const record = recordSchema.parse(result.record);
      if (record.user_id !== input.subject || record.id !== input.record.id)
        throw new Error('training_mutation_record_mismatch');
      return { kind: 'saved', record };
    },
  };
}
