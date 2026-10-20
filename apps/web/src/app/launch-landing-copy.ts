import { logYourBody } from '@jovieinc/product-registry';
import { waitlistLandingCopy } from './waitlist-copy';

const proPlan = logYourBody.plans[0];

function formatPrice(amount: number) {
  return `$${amount.toFixed(2)}`;
}

/**
 * Every line here is a product truth from the registry, a customer outcome, or
 * an action. Feature descriptions come straight from the registry so the page
 * can never claim more than the app ships.
 */
export const launchLandingCopy = {
  headline: logYourBody.messages.landing.headline,
  subheading: logYourBody.messages.landing.subheading,
  appStoreCta: logYourBody.messages.landing.primaryCta,
  waitlistCta: waitlistLandingCopy.submitLabel,
  platformNote: 'iPhone. Weight and steps read from Apple Health.',
  heroImageAlt:
    "LogYourBody Home showing today's weight, the change over 30 days, a trend line, and rows for body fat, FFMI, lean mass and steps.",
  signals: [
    {
      title: 'Weight, read for you',
      body: 'Apple Health fills the timeline. Type a number when you would rather.',
    },
    {
      title: 'Estimates say so',
      body: 'Body fat, lean mass and FFMI are labelled measured or estimated, with their source.',
    },
    {
      title: 'Photos next to the numbers',
      body: 'Private progress photos sit on the same timeline as every entry.',
    },
  ],
  featuresHeading: 'What it keeps',
  pricingHeading: proPlan.name,
  pricingLine: `${proPlan.trialDays}-day free trial, then ${formatPrice(proPlan.pricing.monthly.amount)} a month or ${formatPrice(proPlan.pricing.annual.amount)} a year.`,
  pricingNote: 'Billed through the App Store. Cancel there any time.',
} as const;

export const launchLandingFeatures = logYourBody.features
  .filter((feature) => feature.marketing && feature.availability === 'available')
  .map((feature) => ({ id: feature.id, name: feature.name, description: feature.description }));
