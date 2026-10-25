import { z } from 'zod';
import { CATALOG_EQUIPMENT } from '@/lib/training/catalog';
import type { NativeAccountAdmission } from './native-account-admission';

/** Only user-confirmed inventory. An empty set is distinct from no selected gym. */
export const GymSchema = z
  .object({
    id: z.string().uuid(),
    name: z.string().trim().min(1).max(100),
    region: z.string().trim().max(100).nullable().default(null),
    equipment: z.array(z.enum(CATALOG_EQUIPMENT)).max(CATALOG_EQUIPMENT.length),
    preferredMachines: z.array(z.string().trim().min(1).max(100)).max(50),
  })
  .strict();

export type Gym = z.infer<typeof GymSchema>;

export interface GymRegistryPort {
  list(subject: string): Promise<Gym[]>;
  save(admission: NativeAccountAdmission, gym: Gym): Promise<boolean>;
  remove(admission: NativeAccountAdmission, id: string): Promise<void>;
}
