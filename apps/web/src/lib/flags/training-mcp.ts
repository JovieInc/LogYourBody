/** Default-off server admission. Both the MCP and its training API must be enabled. */
export function trainingMcpEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.LYB_CHATGPT_MCP_ENABLED === 'true' && env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true';
}
