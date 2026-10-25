import { z } from 'zod';
import { MUSCLE_GROUPS } from './types';

export const cycleConfigurationSchema = z
  .object({
    blockId: z.string().min(1).optional(),
    weekCount: z.union([z.literal(4), z.literal(5), z.literal(6)]),
    temporaryPriorities: z.array(z.enum(MUSCLE_GROUPS)).max(10),
    temporaryConstraints: z
      .array(
        z
          .object({ muscle: z.enum(MUSCLE_GROUPS), reason: z.string().trim().min(1).max(500) })
          .strict(),
      )
      .max(10),
    retainedVariants: z
      .array(
        z
          .object({
            fromExerciseId: z.string().min(1),
            toVariantId: z.string().min(1),
            reason: z.string().trim().min(1).max(500),
          })
          .strict(),
      )
      .max(24),
    historyProgramIds: z.array(z.string().uuid()).max(100),
  })
  .strict();
