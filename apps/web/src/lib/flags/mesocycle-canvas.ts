/**
 * Default-off gate for the living mesocycle canvas.
 * Unset or any value other than "true" keeps the surface unavailable.
 * Rollout waits on an installed build of this revision, not on this default.
 */
export const MESOCYCLE_CANVAS_FLAG = 'LYB_MESOCYCLE_CANVAS_ENABLED';

/** Browser harness only. Never enables the canvas by itself. */
export const MESOCYCLE_CANVAS_FIXTURE_FLAG = 'LYB_MESOCYCLE_CANVAS_FIXTURE';

export function mesocycleCanvasEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env[MESOCYCLE_CANVAS_FLAG] === 'true';
}

export function mesocycleCanvasFixtureEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return mesocycleCanvasEnabled(env) && env[MESOCYCLE_CANVAS_FIXTURE_FLAG] === 'true';
}

/** Account mutations stay behind both the coach API and the canvas flag. */
export function mesocycleCanvasApiEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true' && mesocycleCanvasEnabled(env);
}
