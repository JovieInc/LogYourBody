import { logYourBody } from '@jovieinc/product-registry';

const proPlan = logYourBody.plans[0];
const monthlyEquivalent = Number((proPlan.pricing.annual.amount / 12).toFixed(2));
const annualAtMonthlyPrice = proPlan.pricing.monthly.amount * 12;
const annualSavings = Number((annualAtMonthlyPrice - proPlan.pricing.annual.amount).toFixed(2));
const annualSavingsPercent = Math.round((annualSavings / annualAtMonthlyPrice) * 100);

export const APP_CONFIG = {
  // App Identity
  appName: logYourBody.identity.name,
  appNameShort: logYourBody.identity.shortName,
  companyName: logYourBody.identity.legalName,

  // App Store Links
  appStoreUrl: logYourBody.links.appStore,
  playStoreUrl: 'https://play.google.com/store/apps/details?id=com.logyourbody.app', // Coming soon

  // Trial & Subscription
  trialLengthDays: proPlan.trialDays,
  trialLengthText: `${proPlan.trialDays}-day free trial`,

  // Pricing (in USD)
  pricing: {
    monthly: {
      price: proPlan.pricing.monthly.amount,
      period: 'month',
      yearlyTotal: annualAtMonthlyPrice,
    },
    annual: {
      price: proPlan.pricing.annual.amount,
      period: 'year',
      monthlyEquivalent,
      savings: annualSavings,
      savingsPercent: annualSavingsPercent,
    },
  },

  // Social Media URLs
  social: {
    twitter: 'https://twitter.com/logyourbody',
    github: logYourBody.links.github,
    instagram: 'https://instagram.com/logyourbody',
    youtube: 'https://youtube.com/@logyourbody',
  },

  // Contact
  contact: {
    support: logYourBody.contacts.support,
    privacy: logYourBody.contacts.privacy,
    legal: logYourBody.contacts.legal,
    careers: logYourBody.contacts.careers,
  },

  // Company Info
  company: {
    address: {
      street: '123 Fitness Street',
      city: 'San Francisco',
      state: 'CA',
      zip: '94105',
      country: 'USA',
    },
    founded: 2023,
  },

  // Feature Flags
  features: {
    webAppEnabled: true, // Web app is now live
    androidAppEnabled: false, // Coming soon
    removeOriginalsEnabled: true, // New privacy feature
  },

  // App Metadata
  metadata: {
    currentVersion: '2.0.0',
    minimumIOSVersion: '15.0',
  },

  // Analytics & Tracking
  analytics: {
    googleAnalyticsId: process.env.NEXT_PUBLIC_GA_ID,
    mixpanelToken: process.env.NEXT_PUBLIC_MIXPANEL_TOKEN,
  },

  // PWA Configuration
  pwa: {
    themeColor: '#08090a',
    backgroundColor: '#08090a',
    display: 'standalone',
    orientation: 'portrait',
  },
} as const;

// Helper functions
export const getAppStoreUrl = (platform: 'ios' | 'android' = 'ios') => {
  return platform === 'ios' ? APP_CONFIG.appStoreUrl : APP_CONFIG.playStoreUrl;
};

export const getSocialUrl = (platform: keyof typeof APP_CONFIG.social) => {
  return APP_CONFIG.social[platform];
};

export const getContactEmail = (type: keyof typeof APP_CONFIG.contact = 'support') => {
  return APP_CONFIG.contact[type];
};

// Export individual constants for backward compatibility
export const APP_NAME = APP_CONFIG.appName;
export const TRIAL_LENGTH_DAYS = APP_CONFIG.trialLengthDays;
export const APP_STORE_URL = APP_CONFIG.appStoreUrl;
