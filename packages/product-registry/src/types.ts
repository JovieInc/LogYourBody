export type ProductPlatform = 'ios' | 'web' | 'docs';
export type FeatureAvailability = 'available' | 'beta' | 'planned' | 'not-planned';
export type SupportKind = 'email' | 'self-service' | 'community' | 'status';

export interface ProductFeature {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly category: 'measure' | 'understand' | 'privacy' | 'import' | 'support';
  readonly availability: FeatureAvailability;
  readonly platforms: readonly ProductPlatform[];
  readonly entitlement: string;
  readonly marketing: boolean;
}

export interface ProductPlan {
  readonly id: string;
  readonly name: string;
  readonly tagline: string;
  readonly entitlement: string;
  readonly featureIds: readonly string[];
  readonly trialDays: number;
  readonly pricing: {
    readonly currency: 'USD';
    readonly source: 'app-store-connect';
    readonly monthly: {
      readonly amount: number;
      readonly productId: string;
      readonly packageId: string;
    };
    readonly annual: {
      readonly amount: number;
      readonly productId: string;
      readonly packageId: string;
    };
  };
}

export interface ProductDefinition {
  readonly schemaVersion: 1;
  readonly id: string;
  readonly identity: {
    readonly name: string;
    readonly shortName: string;
    readonly legalName: string;
    readonly domain: string;
    readonly bundleId: string;
    readonly appStoreId: string;
  };
  readonly brand: {
    readonly promise: string;
    readonly slogan: string;
    readonly description: string;
    readonly voice: readonly string[];
    readonly colors: {
      readonly background: string;
      readonly foreground: string;
      readonly accent: string;
    };
    readonly logos: {
      readonly appIcon: string;
      readonly wordmark: string | null;
      readonly mark: string | null;
    };
  };
  readonly links: {
    readonly home: string;
    readonly appStore: string;
    readonly github: string;
    readonly privacy: string;
    readonly terms: string;
    readonly support: string;
    readonly status: string;
  };
  readonly contacts: {
    readonly support: string;
    readonly privacy: string;
    readonly legal: string;
    readonly careers: string;
  };
  readonly support: readonly {
    readonly id: string;
    readonly kind: SupportKind;
    readonly label: string;
    readonly description: string;
    readonly href: string;
    readonly responseTime?: string;
    readonly public: boolean;
  }[];
  readonly messages: {
    readonly landing: {
      readonly headline: string;
      readonly subheading: string;
      readonly framingLine: string;
      readonly primaryCta: string;
    };
    readonly waitlist: {
      readonly success: string;
      readonly duplicate: string;
      readonly error: string;
      readonly invalidEmail: string;
    };
    readonly paywall: {
      readonly title: string;
      readonly subtitle: string;
      readonly valueProposition: string;
    };
  };
  readonly features: readonly ProductFeature[];
  readonly plans: readonly ProductPlan[];
  readonly surfaces: readonly {
    readonly id: string;
    readonly label: string;
    readonly route: string;
    readonly platform: ProductPlatform;
    readonly status: 'canonical' | 'supporting' | 'deferred';
    readonly purpose: string;
  }[];
  readonly landingPages: readonly {
    readonly id: string;
    readonly route: string;
    readonly audience: string;
    readonly goal: string;
    readonly sectionOrder: readonly string[];
    readonly status: 'canonical' | 'experiment' | 'rollback';
  }[];
}
