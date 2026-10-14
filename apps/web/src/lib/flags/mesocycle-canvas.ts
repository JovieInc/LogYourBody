/**
 * Server admission for the living mesocycle canvas.
 * Unset or any value other than "1" keeps the surface off.
 * Native clients also require the Statsig gate `mesocycle_canvas_v1`.
 */
export const MESOCYCLE_CANVAS_FLAG = 'LYB_MESOCYCLE_CANVAS_V1';
export const MESOCYCLE_CANVAS_GATE = 'mesocycle_canvas_v1';

export function mesocycleCanvasEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env[MESOCYCLE_CANVAS_FLAG] === '1';
}
