import { z } from 'zod';
import { structuredTrainingRecord } from '@/lib/training/outbound-policy';

const setLog = z.strictObject({
  sessionId: z.string(),
  exerciseId: z.string(),
  setNumber: z.number().int(),
  reps: z.number().int(),
  loadKg: z.number().finite().nullable(),
  rir: z.number().int(),
  completedAt: z.string().optional(),
});

/** Canonical v1 data boundary (LYB-279). Future handlers must parse reads and writes. */
export const TRAINING_MCP_V1_ALLOWLIST = Object.freeze({
  read_plan: structuredTrainingRecord(
    z.strictObject({
      sessionId: z.string(),
      exercises: z.array(
        z.strictObject({
          exerciseId: z.string(),
          name: z.string(),
          sets: z.number().int(),
          targetReps: z.number().int(),
          repRange: z.strictObject({ min: z.number().int(), max: z.number().int() }),
          targetRir: z.number().int(),
          targetLoadKg: z.number().finite().nullable(),
          evidenceIds: z.array(z.string()),
        }),
      ),
    }),
  ),
  log_set: structuredTrainingRecord(setLog),
  log_check_in: structuredTrainingRecord(z.strictObject({ completed: z.boolean() })),
  read_progress: structuredTrainingRecord(
    z.strictObject({
      sets: z.array(setLog),
      lastUsedLoad: z.array(
        z.strictObject({ exerciseId: z.string(), loadKg: z.number().finite().nullable() }),
      ),
      checkInCompleted: z.boolean(),
    }),
  ),
});
