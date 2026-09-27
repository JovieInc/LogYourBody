import { connectionStateFromAttributes, type LogYourBodyConnectionState } from './account-connection';

export type TrainingToolPrincipal = {
  attributes?: Record<string, unknown> | null;
  principalType?: string;
  subject?: string;
} | null;

export type TrainingToolGate =
  | { available: false; status: 'connection_required' }
  | { available: false; status: 'first_party_auth_required' };

export function trainingToolGate(principal: TrainingToolPrincipal): TrainingToolGate {
  const state: LogYourBodyConnectionState = connectionStateFromAttributes(principal?.attributes);
  if (state !== 'connected') return { available: false, status: 'connection_required' };

  // The current channel uses placeholder auth and carries no scoped first-party
  // bearer token. Do not read or mutate product records until that boundary ships.
  if (principal?.principalType !== 'user' || !principal.subject) {
    return { available: false, status: 'first_party_auth_required' };
  }
  return { available: false, status: 'first_party_auth_required' };
}
