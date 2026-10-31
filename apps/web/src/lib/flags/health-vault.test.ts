import { healthVaultEnabled } from './health-vault';

const both = {
  LYB_HEALTH_VAULT_ENABLED: 'true',
  LYB_CHATGPT_MCP_ENABLED: 'true',
};

describe('healthVaultEnabled', () => {
  it('stays closed without both switches and an explicit gate', () => {
    expect(healthVaultEnabled({})).toBe(false);
    expect(healthVaultEnabled(both)).toBe(false);
    expect(healthVaultEnabled(both, false)).toBe(false);
  });

  it('opens when both switches are on and the gate is explicit', () => {
    expect(healthVaultEnabled({ ...both, LYB_HEALTH_VAULT_GATE_OVERRIDE: 'on' })).toBe(true);
    expect(healthVaultEnabled(both, true)).toBe(true);
  });

  it('lets an off override force the gate closed', () => {
    expect(healthVaultEnabled({ ...both, LYB_HEALTH_VAULT_GATE_OVERRIDE: 'off' }, true)).toBe(
      false,
    );
  });

  it('does not open from the weight-agent switches', () => {
    expect(
      healthVaultEnabled({
        ...both,
        LYB_METRICS_AGENT_ENABLED: 'true',
        LYB_METRICS_AGENT_GATE_OVERRIDE: 'on',
      }),
    ).toBe(false);
  });
});
