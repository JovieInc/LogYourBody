import { analytics } from '@/lib/analytics';

export const INDIVIDUALIZED_AESTHETIC_GOALS_GATE = 'individualized_aesthetic_goals';

export function usesIndividualizedAestheticGoals(): boolean {
  return analytics.isFeatureEnabled(INDIVIDUALIZED_AESTHETIC_GOALS_GATE);
}
