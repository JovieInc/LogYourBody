import { z } from 'zod';
import { planningInputsSchema } from '@/lib/training/delegation-contract';
import type {
  NativeAccountAdmission,
  NativeAccountAdmissionPort,
} from './native-account-admission';

const interval = z
  .object({ start: z.string().date(), end: z.string().date() })
  .strict()
  .refine((v) => v.start <= v.end);
const availabilitySchema = planningInputsSchema.omit({ goal: true, goalDate: true }).partial();

// Wire fields follow Jovie's lyb-launch-contract/v1 required inputs. Policy stays upstream.
export const datedOutcomeSchema = z
  .object({
    outcome: z
      .object({
        metric: z.enum(['weight_kg', 'body_fat_percentage', 'ffmi']),
        targetValue: z.number().finite().positive(),
      })
      .strict(),
    outcomeDate: z.string().date(),
    constraints: z
      .object({
        availability: availabilitySchema,
        travel: z.array(interval).max(100),
        maintenance: z.array(interval).max(100),
      })
      .strict(),
  })
  .strict();

export const datedOutcomeEditSchema = z
  .object({
    requestId: z.string().uuid(),
    previousRevision: z.string().uuid().nullable(),
    value: datedOutcomeSchema,
  })
  .strict();
export type DatedOutcome = z.infer<typeof datedOutcomeSchema>;
export type DatedOutcomeEdit = z.infer<typeof datedOutcomeEditSchema>;
export type DatedOutcomeSnapshot = { revision: string; value: DatedOutcome };
export type DatedOutcomeSaveResult =
  | { kind: 'saved'; snapshot: DatedOutcomeSnapshot }
  | { kind: 'revision_conflict' | 'request_conflict' };

/** A partial LYB-130 input update, never a prescription or an accepted program revision.
 * Travel/maintenance remain explicit request context; no invented schedule translation. */
export function datedOutcomePlanInputs(value: DatedOutcome) {
  return planningInputsSchema.partial().parse({
    ...value.constraints.availability,
    goal: `${value.outcome.metric}: ${value.outcome.targetValue}`,
    goalDate: `${value.outcomeDate}T00:00:00Z`,
  });
}

export interface DatedOutcomePort extends NativeAccountAdmissionPort {
  read(subject: string): Promise<DatedOutcomeSnapshot | null>;
  save(admission: NativeAccountAdmission, edit: DatedOutcomeEdit): Promise<DatedOutcomeSaveResult>;
}
