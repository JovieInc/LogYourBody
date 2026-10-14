/**
 * Default-off gate for mesocycle optimization proposals.
 * Unset or any value other than "true" keeps optimization unavailable.
 * Rollout waits on an installed build of this revision, not on this default.
 */
export const MESOCYCLE_OPTIMIZER_FLAG = 'LYB_MESOCYCLE_OPTIMIZER_ENABLED';

export function mesocycleOptimizerEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env[MESOCYCLE_OPTIMIZER_FLAG] === 'true';
}
