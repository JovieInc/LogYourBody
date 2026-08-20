export type LogYourBodyConnectionState = 'connected' | 'unconnected';

export function connectionStateFromAttributes(
  attributes: Record<string, unknown> | null | undefined,
): LogYourBodyConnectionState {
  return attributes?.logYourBodyConnection === 'connected' ? 'connected' : 'unconnected';
}

export function localConnectionFixture(): LogYourBodyConnectionState {
  if (process.env.LYB_EVE_LOCAL_SMOKE !== '1') return 'unconnected';
  return process.env.LYB_EVE_CONNECTION_FIXTURE === 'connected' ? 'connected' : 'unconnected';
}

export function connectionInstruction(state: LogYourBodyConnectionState): string {
  if (state === 'connected') {
    return 'The caller has a server-verified LogYourBody account connection. This does not grant health-data access by itself. Use only the explicit scopes and data returned by authorized first-party tools.';
  }

  return 'The caller does not have a server-verified LogYourBody account connection. Do not claim access to health data. Explain that they need to connect LogYourBody through the first-party connection flow before health-related work can use their data.';
}

export function smokeReply(state: LogYourBodyConnectionState, turn: number): string {
  if (state === 'connected') {
    return `Connected boundary verified on turn ${turn}; no health-data tool is enabled.`;
  }

  return `Connect LogYourBody before health-data work. No health data was accessed on turn ${turn}.`;
}
