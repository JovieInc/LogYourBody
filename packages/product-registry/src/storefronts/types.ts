export type StorefrontCustomProductPageStatus = 'candidate' | 'active' | 'deferred';
export type StorefrontScreenshotStatus = 'hypothesis' | 'approved' | 'retired';
export type StorefrontExperimentStatus =
  | 'draft'
  | 'ready'
  | 'running'
  | 'winner'
  | 'loser'
  | 'inconclusive'
  | 'stopped';
export type StorefrontExperimentMechanism =
  | 'product-page-optimization'
  | 'custom-product-page'
  | 'metadata-release';

export interface StorefrontLocaleMetadata {
  readonly name: string;
  readonly subtitle: string;
  readonly keywords: string;
  readonly promotionalText: string;
  readonly description: string;
  readonly releaseNotes: string;
  readonly supportUrl: string;
  readonly marketingUrl: string;
  readonly privacyUrl: string;
}

export interface StorefrontLocale {
  readonly id: string;
  readonly metadata: StorefrontLocaleMetadata;
}

export interface StorefrontSearchIntent {
  readonly id: string;
  readonly label: string;
  readonly audience: string;
  readonly priority: number;
  readonly terms: readonly string[];
  readonly featureIds: readonly string[];
  readonly customProductPageStatus: StorefrontCustomProductPageStatus;
}

export interface StorefrontScreenshotFrame {
  readonly id: string;
  readonly order: number;
  readonly headline: string;
  readonly supportingCopy: string;
  readonly captureStateId: string;
  readonly featureIds: readonly string[];
}

export interface StorefrontScreenshotSet {
  readonly id: string;
  readonly locale: string;
  readonly target: 'iphone-6.9';
  readonly status: StorefrontScreenshotStatus;
  readonly frames: readonly StorefrontScreenshotFrame[];
}

export interface StorefrontExperiment {
  readonly id: string;
  readonly mechanism: StorefrontExperimentMechanism;
  readonly intentId: string;
  readonly hypothesis: string;
  readonly status: StorefrontExperimentStatus;
  readonly baselineAssetIds: readonly string[];
  readonly treatmentAssetIds: readonly string[];
  readonly primaryMetric: string;
  readonly guardrailMetrics: readonly string[];
  readonly startedAt: string | null;
  readonly endedAt: string | null;
  readonly resultSummary: string | null;
}

export interface ProductStorefrontDefinition {
  readonly schemaVersion: 1;
  readonly productId: string;
  readonly platform: 'ios';
  readonly defaultLocale: string;
  readonly metadataLimits: {
    readonly nameCharacters: number;
    readonly subtitleCharacters: number;
    readonly promotionalTextCharacters: number;
    readonly descriptionCharacters: number;
    readonly releaseNotesCharacters: number;
    readonly keywordsBytes: number;
  };
  readonly locales: readonly StorefrontLocale[];
  readonly searchIntents: readonly StorefrontSearchIntent[];
  readonly screenshotPolicy: {
    readonly minimumCount: number;
    readonly maximumCount: number;
    readonly preferredPortraitSize: {
      readonly width: number;
      readonly height: number;
    };
    readonly acceptedPortraitSizes: readonly {
      readonly width: number;
      readonly height: number;
    }[];
    readonly alphaAllowed: false;
    readonly finalProductUiSource: 'real-app-capture';
    readonly provenanceRequired: true;
  };
  readonly screenshotSets: readonly StorefrontScreenshotSet[];
  readonly measurement: {
    readonly primaryMetric: string;
    readonly guardrailMetrics: readonly string[];
  };
  readonly experiments: readonly StorefrontExperiment[];
  readonly creative: {
    readonly imageModel: string;
    readonly approvedDirection: string | null;
    readonly allowedImageUses: readonly string[];
    readonly prohibitedImageUses: readonly string[];
  };
}
