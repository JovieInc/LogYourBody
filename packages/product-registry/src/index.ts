export type {
  FeatureAvailability,
  ProductAllowlistEntry,
  ProductDefinition,
  ProductEndpointHost,
  ProductEndpoints,
  ProductFeature,
  ProductPlan,
  ProductPlatform,
  SupportKind,
} from './types.js';
export type {
  ProductStorefrontDefinition,
  StorefrontExperiment,
  StorefrontExperimentMechanism,
  StorefrontExperimentStatus,
  StorefrontCustomProductPageStatus,
  StorefrontLocale,
  StorefrontLocaleMetadata,
  StorefrontScreenshotFrame,
  StorefrontScreenshotSet,
  StorefrontScreenshotStatus,
  StorefrontSearchIntent,
} from './storefronts/types.js';
export { logYourBody } from './products/logyourbody.mjs';
export { logYourBodyStorefront } from './storefronts/logyourbody.mjs';

import { logYourBody } from './products/logyourbody.mjs';
import { logYourBodyStorefront } from './storefronts/logyourbody.mjs';

export const PRODUCT_REGISTRY = { logyourbody: logYourBody } as const;
export const STOREFRONT_REGISTRY = { logyourbody: logYourBodyStorefront } as const;
export type ProductId = keyof typeof PRODUCT_REGISTRY;

export function getProduct(id: ProductId) {
  return PRODUCT_REGISTRY[id];
}

export function getStorefront(id: ProductId) {
  return STOREFRONT_REGISTRY[id];
}

export function getFeature(id: string) {
  return logYourBody.features.find((feature) => feature.id === id);
}

export function getPlan(id: string) {
  return logYourBody.plans.find((plan) => plan.id === id);
}

export function getPublicSupportOptions() {
  return logYourBody.support.filter((option) => option.public);
}
