// Central constants file for LogYourBody
// These values should be kept in sync with iOS app constants

export const APP_CONFIG = {
  // App Identity
  appName: 'LogYourBody',
  appNameShort: 'LYB',
  companyName: 'LogYourBody, Inc.',
  
  // App Store Links
  appStoreUrl: 'https://apps.apple.com/app/logyourbody/id6444302778',
  playStoreUrl: 'https://play.google.com/store/apps/details?id=com.logyourbody.app', // Coming soon
  
  // Trial & Subscription
  trialLengthDays: 7,
  trialLengthText: '7-day free trial',
  
  // Pricing (in USD)
  pricing: {
    monthly: {
      price: 9.99,
      period: 'month',
      yearlyTotal: 119.88,
    },
    annual: {
      price: 69.99,
      period: 'year',
      monthlyEquivalent: 5.83,
      savings: 49.89,
      savingsPercent: 42,
    },
  },
  
  // Social Media URLs
  social: {
    twitter: 'https://twitter.com/logyourbody',
    github: 'https://github.com/JovieInc/LogYourBody',
    instagram: 'https://instagram.com/logyourbody',
    youtube: 'https://youtube.com/@logyourbody',
  },
  
  // Contact
  contact: {
    support: 'support@logyourbody.com',
    privacy: 'privacy@logyourbody.com',
    legal: 'legal@logyourbody.com',
    careers: 'careers@logyourbody.com',
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
    appStoreRating: 4.9,
    totalUsers: '10,000+',
    successRate: '93%',
  },
  
  // API & Backend
  api: {
    baseUrl: process.env.NEXT_PUBLIC_API_URL || 'https://api.logyourbody.com',
    websocketUrl: process.env.NEXT_PUBLIC_WS_URL || 'wss://api.logyourbody.com',
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