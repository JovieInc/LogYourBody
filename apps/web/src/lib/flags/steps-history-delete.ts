/** Server availability control, separate from the native Statsig gate.
 * Existing deletion markers are honored regardless of this creation gate.
 */
export const STEPS_HISTORY_DELETE_GATE = 'steps_history_delete_v1';
export const STEPS_HISTORY_DELETE_SERVER_FLAG = 'LYB_STEPS_HISTORY_DELETE_V1_ENABLED';

export function stepsHistoryDeleteEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return env[STEPS_HISTORY_DELETE_SERVER_FLAG] === 'true';
}
