import type { TrunkDemand, TrunkDemandLevel } from './catalog-schema';

const reviewed = (level: TrunkDemandLevel, note: string): TrunkDemand => ({
  level,
  basis: 'reviewed',
  note,
});

export { reviewed };
