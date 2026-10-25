import { z } from 'zod';
import { CATALOG_EQUIPMENT } from '@/lib/training/catalog';

const name = z.string().trim().min(1).max(120);
export const gymSchema = z
  .object({
    id: z.string().uuid(),
    name,
    // Swift omits nil optional fields when a region has not been entered.
    coarseRegion: name.nullable().default(null),
    // An explicit empty inventory is different from no selected gym.
    equipment: z
      .array(z.enum(CATALOG_EQUIPMENT))
      .max(CATALOG_EQUIPMENT.length)
      .refine((items) => new Set(items).size === items.length),
    preferredMachines: z.array(name).max(30),
  })
  .strict();
export const gymRecordSchema = z.object({ gym: gymSchema, deleted: z.boolean() }).strict();
export const gymChangesSchema = z
  .object({ changes: z.array(gymRecordSchema).min(1).max(100) })
  .strict()
  .refine(
    ({ changes }) =>
      new Set(changes.map((item) => item.gym.id.toLowerCase())).size === changes.length,
  );
export type GymRecord = z.infer<typeof gymRecordSchema>;

export interface GymRegistryPort {
  /** Full snapshot including tombstones; active choice is device-local. */
  sync(subject: string, changes?: GymRecord[]): Promise<GymRecord[]>;
}
