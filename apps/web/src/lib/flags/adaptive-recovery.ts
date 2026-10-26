/** Existing coach admission plus a separate default-off recovery rollout. */
export function adaptiveRecoveryEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return (
    env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true' && env.LYB_ADAPTIVE_RECOVERY_ENABLED === 'true'
  );
}
