import { APP_CONFIG } from '@/constants/app';
import { logYourBody } from '@jovieinc/product-registry';

export const landingSectionHeadings = {
  hero: logYourBody.identity.name,
  photos: 'The mirror gets a memory.',
  features: 'Everything important. Nothing noisy.',
  timeline: 'Your body over time.',
  pricing: 'Start with one clean body log.',
} as const;

export function getPricingPlanNote(isAnnual: boolean) {
  if (!isAnnual) {
    return 'Switch anytime when you are ready.';
  }

  return `$${APP_CONFIG.pricing.annual.monthlyEquivalent}/month equivalent. Save ${APP_CONFIG.pricing.annual.savingsPercent}%.`;
}
