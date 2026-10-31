/** Default-off admission for the ChatGPT health vault.
 * Both env switches must be on, and the platform gate must be explicitly open.
 * A missing Statsig evaluation stays closed. Training and weight flags do not open this.
 */
export const HEALTH_VAULT_GATE = 'health_vault_chatgpt';

export function healthVaultEnabled(
  env: { [key: string]: string | undefined } = process.env,
  gateOpen = false,
): boolean {
  if (env.LYB_HEALTH_VAULT_ENABLED !== 'true') return false;
  if (env.LYB_CHATGPT_MCP_ENABLED !== 'true') return false;
  if (env.LYB_HEALTH_VAULT_GATE_OVERRIDE === 'off') return false;
  return env.LYB_HEALTH_VAULT_GATE_OVERRIDE === 'on' || gateOpen === true;
}
