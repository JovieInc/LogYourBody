import { logYourBody } from '@jovieinc/product-registry';
import { waitlistLandingCopy } from './waitlist-copy';

const proPlan = logYourBody.plans[0];

function formatPrice(amount: number) {
  return `$${amount.toFixed(2)}`;
}

/**
 * Feature descriptions and reference prices use the canonical registry.
 * Implemented behavior and public release availability still need their own
 * runtime/provider evidence; a registry entry is not proof of shipment.
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
  pricingLine: `Reference pricing: ${formatPrice(proPlan.pricing.monthly.amount)} a month or ${formatPrice(proPlan.pricing.annual.amount)} a year (USD).`,
  pricingNote:
    'The App Store confirms your local price, any trial eligibility, and subscription terms before you subscribe. Manage or cancel your subscription there.',
} as const;

export const launchLandingFeatures = logYourBody.features
  .filter((feature) => feature.marketing && feature.availability === 'available')
  .map((feature) => ({ id: feature.id, name: feature.name, description: feature.description }));
