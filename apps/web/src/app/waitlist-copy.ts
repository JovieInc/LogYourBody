import { logYourBody } from '@jovieinc/product-registry';

export const waitlistLandingCopy = {
  headline: logYourBody.messages.landing.headline,
  subheading: logYourBody.messages.landing.subheading,
  emailLabel: 'Email',
  emailPlaceholder: 'you@example.com',
  submitLabel: 'Request early access',
  successMessage: logYourBody.messages.waitlist.success,
  duplicateMessage: logYourBody.messages.waitlist.duplicate,
  errorMessage: logYourBody.messages.waitlist.error,
  invalidEmailMessage: logYourBody.messages.waitlist.invalidEmail,
} as const;
