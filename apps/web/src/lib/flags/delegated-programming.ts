/** Default-off server admission for the delegated programming rollout. Native
 * also checks its Platform feature gate before presenting the new flow. */
export function delegatedProgrammingEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return (
    env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true' &&
    env.LYB_DELEGATED_PROGRAMMING_ENABLED === 'true'
  );
}
