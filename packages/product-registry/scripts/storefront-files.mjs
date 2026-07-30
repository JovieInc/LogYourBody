import { resolve } from 'node:path';
import { logYourBodyStorefront } from '../src/storefronts/logyourbody.mjs';
import { collectScreenshotAssets } from './storefront-assets.mjs';

const metadataFileNames = {
  name: 'name.txt',
  subtitle: 'subtitle.txt',
  keywords: 'keywords.txt',
  promotionalText: 'promotional_text.txt',
  description: 'description.txt',
  releaseNotes: 'release_notes.txt',
  supportUrl: 'support_url.txt',
  marketingUrl: 'marketing_url.txt',
  privacyUrl: 'privacy_url.txt',
};

const normalizeMetadata = (value) => `${value.replace(/\s+$/u, '')}\n`;

export async function storefrontManifest(repoRoot) {
  return {
    generatedBy: 'packages/product-registry/scripts/generate-storefront.mjs',
    ...logYourBodyStorefront,
    assetProvenance: {
      screenshots: await collectScreenshotAssets(repoRoot),
    },
  };
}

export async function expectedStorefrontFiles(repoRoot) {
  const files = new Map();

  for (const locale of logYourBodyStorefront.locales) {
    for (const [field, filename] of Object.entries(metadataFileNames)) {
      files.set(
        resolve(repoRoot, 'apps/ios/fastlane/metadata', locale.id, filename),
        normalizeMetadata(locale.metadata[field]),
      );
    }
  }

  files.set(
    resolve(repoRoot, 'apps/ios/fastlane/storefront-manifest.generated.json'),
    `${JSON.stringify(await storefrontManifest(repoRoot), null, 2)}\n`,
  );

  return files;
}
