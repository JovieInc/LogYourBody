/**
 * Server gate for the coach persona and clinical guardrails.
 * Unset or any value other than "1" keeps the current chat path.
 */
export const COACH_PERSONA_GUARDRAILS_FLAG = 'LYB_COACH_PERSONA_GUARDRAILS_V1';

export function coachPersonaGuardrailsEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env[COACH_PERSONA_GUARDRAILS_FLAG] === '1';
}
