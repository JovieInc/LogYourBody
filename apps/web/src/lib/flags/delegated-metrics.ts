/** Default-off admission for delegated manual weight actions.
 * Both env switches must be on, and the platform gate must be explicitly open.
 * A missing Statsig evaluation stays closed. Training flags do not open this. */
export const METRICS_AGENT_WEIGHT_GATE = 'metrics_agent_weight_lifecycle';

export function delegatedMetricsEnabled(
  env: NodeJS.ProcessEnv = process.env,
  gateOpen = false,
): boolean {
  if (env.LYB_METRICS_AGENT_ENABLED !== 'true') return false;
  if (env.LYB_CHATGPT_MCP_ENABLED !== 'true') return false;
  if (env.LYB_METRICS_AGENT_GATE_OVERRIDE === 'off') return false;
  return env.LYB_METRICS_AGENT_GATE_OVERRIDE === 'on' || gateOpen === true;
}
