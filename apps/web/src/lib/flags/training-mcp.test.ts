import { trainingMcpEnabled } from './training-mcp';

describe('training MCP admission (LYB-280)', () => {
  it('defaults off with no configuration', () => {
    expect(trainingMcpEnabled({})).toBe(false);
  });

  it.each([undefined, '', 'false', 'TRUE', '1'])('%s does not enable either switch', (value) => {
    expect(
      trainingMcpEnabled({
        LYB_CHATGPT_MCP_ENABLED: value,
        LYB_HYPERTROPHY_COACH_API_ENABLED: 'true',
      }),
    ).toBe(false);
    expect(
      trainingMcpEnabled({
        LYB_CHATGPT_MCP_ENABLED: 'true',
        LYB_HYPERTROPHY_COACH_API_ENABLED: value,
      }),
    ).toBe(false);
  });

  it('requires explicit enablement of both the MCP and training API', () => {
    expect(
      trainingMcpEnabled({
        LYB_CHATGPT_MCP_ENABLED: 'true',
        LYB_HYPERTROPHY_COACH_API_ENABLED: 'true',
      }),
    ).toBe(true);
  });

  it('reads the current server environment when called without arguments', () => {
    const previous = process.env;
    try {
      process.env = { ...previous };
      delete process.env.LYB_CHATGPT_MCP_ENABLED;
      delete process.env.LYB_HYPERTROPHY_COACH_API_ENABLED;
      expect(trainingMcpEnabled()).toBe(false);
      process.env.LYB_CHATGPT_MCP_ENABLED = 'true';
      process.env.LYB_HYPERTROPHY_COACH_API_ENABLED = 'true';
      expect(trainingMcpEnabled()).toBe(true);
    } finally {
      process.env = previous;
    }
  });
});
