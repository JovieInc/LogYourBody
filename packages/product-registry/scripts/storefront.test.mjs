import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { logYourBody } from '../src/products/logyourbody.mjs';
import { logYourBodyStorefront } from '../src/storefronts/logyourbody.mjs';
import { collectScreenshotAssets } from './storefront-assets.mjs';
import { expectedStorefrontFiles } from './storefront-files.mjs';

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = resolve(packageRoot, '../..');
const storefront = logYourBodyStorefront;
const featureById = new Map(logYourBody.features.map((feature) => [feature.id, feature]));

const unique = (values, message) => {
  assert.equal(new Set(values).size, values.length, message);
};

const characters = (value) => [...value].length;
const normalizeWords = (value) =>
  value
    .replace(/([a-z])([A-Z])/gu, '$1 $2')
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean);

const assertMarketableFeatureReferences = (owner, featureIds) => {
  unique(featureIds, `${owner} must not repeat feature references`);

  for (const featureId of featureIds) {
    const feature = featureById.get(featureId);
    assert(feature, `${owner} references unknown feature ${featureId}`);
    assert.equal(feature.availability, 'available', `${owner} references unavailable ${featureId}`);
    assert.equal(feature.marketing, true, `${owner} references non-marketable ${featureId}`);
    assert(feature.platforms.includes('ios'), `${owner} references non-iOS feature ${featureId}`);
  }
};

assert.equal(storefront.productId, logYourBody.id);
assert.equal(storefront.platform, 'ios');
assert.equal(storefront.screenshotPolicy.finalProductUiSource, 'real-app-capture');
assert.equal(storefront.screenshotPolicy.alphaAllowed, false);
assert.equal(storefront.screenshotPolicy.provenanceRequired, true);
assert.match(
  storefront.creative.imageModel,
  /^gpt-image-2-\d{4}-\d{2}-\d{2}$/u,
  'production image generation must use a pinned GPT Image 2 snapshot',
);
assert(
  storefront.creative.prohibitedImageUses.includes('product UI'),
  'GPT Image 2 must never become the source of truth for product UI',
);
assert(
  storefront.creative.prohibitedImageUses.includes('generated body transformations'),
  'generated body transformations must remain prohibited',
);

const localeIds = storefront.locales.map((locale) => locale.id);
unique(localeIds, 'storefront locale IDs must be unique');
assert(localeIds.includes(storefront.defaultLocale), 'default locale must exist');

for (const locale of storefront.locales) {
  const { metadata } = locale;
  const limits = storefront.metadataLimits;

  assert(
    characters(metadata.name) >= 2 && characters(metadata.name) <= limits.nameCharacters,
    `${locale.id} name must be 2-${limits.nameCharacters} characters`,
  );
  assert(
    characters(metadata.subtitle) <= limits.subtitleCharacters,
    `${locale.id} subtitle exceeds ${limits.subtitleCharacters} characters`,
  );
  assert(
    characters(metadata.promotionalText) <= limits.promotionalTextCharacters,
    `${locale.id} promotional text exceeds ${limits.promotionalTextCharacters} characters`,
  );
  assert(
    characters(metadata.description) <= limits.descriptionCharacters,
    `${locale.id} description exceeds ${limits.descriptionCharacters} characters`,
  );
  assert(
    characters(metadata.releaseNotes) <= limits.releaseNotesCharacters,
    `${locale.id} release notes exceed ${limits.releaseNotesCharacters} characters`,
  );
  assert(
    Buffer.byteLength(metadata.keywords, 'utf8') <= limits.keywordsBytes,
    `${locale.id} keywords exceed ${limits.keywordsBytes} bytes`,
  );

  const keywords = metadata.keywords.split(',');
  assert.equal(
    metadata.keywords,
    keywords.map((keyword) => keyword.trim()).join(','),
    `${locale.id} keywords must be comma-separated without padding spaces`,
  );
  assert(
    keywords.every((keyword) => characters(keyword) > 2),
    `${locale.id} keywords must exceed two characters`,
  );
  unique(
    keywords.map((keyword) => keyword.toLowerCase()),
    `${locale.id} keywords must be unique`,
  );

  const indexedElsewhere = new Set([
    ...normalizeWords(metadata.name),
    ...normalizeWords(metadata.subtitle),
    ...normalizeWords(logYourBody.identity.legalName),
  ]);
  for (const keyword of keywords) {
    for (const word of normalizeWords(keyword)) {
      assert(
        !indexedElsewhere.has(word),
        `${locale.id} keyword "${word}" duplicates the app name, subtitle, or company name`,
      );
    }
  }

  assert.equal(metadata.name, logYourBody.identity.name);
  assert.equal(metadata.supportUrl, logYourBody.links.support);
  assert.equal(metadata.marketingUrl, logYourBody.links.home);
  assert.equal(metadata.privacyUrl, logYourBody.links.privacy);
}

const intentIds = storefront.searchIntents.map((intent) => intent.id);
unique(intentIds, 'search-intent IDs must be unique');
unique(
  storefront.searchIntents.map((intent) => intent.priority),
  'search-intent priorities must be unique',
);
assert.deepEqual(
  storefront.searchIntents.map((intent) => intent.priority).sort((a, b) => a - b),
  storefront.searchIntents.map((_, index) => index + 1),
  'search-intent priorities must be contiguous',
);
for (const intent of storefront.searchIntents) {
  assert(intent.terms.length > 0, `${intent.id} needs at least one search term`);
  unique(
    intent.terms.map((term) => term.toLowerCase()),
    `${intent.id} search terms must be unique`,
  );
  assertMarketableFeatureReferences(`search intent ${intent.id}`, intent.featureIds);
}

const screenshotSetIds = storefront.screenshotSets.map((set) => set.id);
unique(screenshotSetIds, 'screenshot-set IDs must be unique');
for (const screenshotSet of storefront.screenshotSets) {
  assert(localeIds.includes(screenshotSet.locale), `${screenshotSet.id} references an unknown locale`);
  assert(
    screenshotSet.frames.length >= storefront.screenshotPolicy.minimumCount &&
      screenshotSet.frames.length <= storefront.screenshotPolicy.maximumCount,
    `${screenshotSet.id} must contain ${storefront.screenshotPolicy.minimumCount}-${storefront.screenshotPolicy.maximumCount} frames`,
  );

  unique(
    screenshotSet.frames.map((frame) => frame.id),
    `${screenshotSet.id} frame IDs must be unique`,
  );
  unique(
    screenshotSet.frames.map((frame) => frame.captureStateId),
    `${screenshotSet.id} capture-state IDs must be unique`,
  );
  assert.deepEqual(
    screenshotSet.frames.map((frame) => frame.order),
    screenshotSet.frames.map((_, index) => index + 1),
    `${screenshotSet.id} frame order must be contiguous`,
  );

  for (const frame of screenshotSet.frames) {
    assert(frame.headline.trim(), `${frame.id} needs a headline`);
    assert(frame.supportingCopy.trim(), `${frame.id} needs supporting copy`);
    assertMarketableFeatureReferences(`screenshot frame ${frame.id}`, frame.featureIds);
  }
}

const experimentIds = storefront.experiments.map((experiment) => experiment.id);
unique(experimentIds, 'experiment IDs must be unique');
for (const experiment of storefront.experiments) {
  assert(intentIds.includes(experiment.intentId), `${experiment.id} references an unknown intent`);
  assert(experiment.hypothesis.trim(), `${experiment.id} needs a hypothesis`);
  assert(experiment.primaryMetric.trim(), `${experiment.id} needs a primary metric`);
  assert(experiment.guardrailMetrics.length > 0, `${experiment.id} needs guardrail metrics`);
  unique(experiment.baselineAssetIds, `${experiment.id} baseline asset IDs must be unique`);
  unique(experiment.treatmentAssetIds, `${experiment.id} treatment asset IDs must be unique`);
}

assert(storefront.measurement.primaryMetric.trim(), 'storefront measurement needs a primary metric');
assert(storefront.measurement.guardrailMetrics.length > 0, 'storefront measurement needs guardrails');
unique(storefront.measurement.guardrailMetrics, 'storefront guardrail metrics must be unique');

for (const [path, expected] of await expectedStorefrontFiles(repoRoot)) {
  const current = await readFile(path, 'utf8').catch(() => '');
  assert.equal(current, expected, `${path} is stale; run pnpm product:generate`);
}

const screenshotAssets = await collectScreenshotAssets(repoRoot);
const acceptedSizes = new Set(
  storefront.screenshotPolicy.acceptedPortraitSizes.map(({ width, height }) => `${width}x${height}`),
);
const modernRequiredSizes = new Set([
  '1260x2736',
  '1290x2796',
  '1320x2868',
  '1284x2778',
  '1242x2688',
]);

for (const locale of storefront.locales) {
  const screenshots = screenshotAssets.filter((asset) => asset.locale === locale.id);
  assert(screenshots.length > 0, `${locale.id} needs at least one PNG screenshot`);

  let hasModernRequiredSize = false;
  const countBySize = new Map();
  for (const screenshot of screenshots) {
    const size = `${screenshot.width}x${screenshot.height}`;

    assert(acceptedSizes.has(size), `${screenshot.filename} uses unsupported portrait size ${size}`);
    assert.equal(
      screenshot.hasAlpha,
      false,
      `${screenshot.filename} contains an alpha channel or transparency`,
    );
    assert.match(screenshot.gitBlobSha, /^[a-f0-9]{40}$/u, `${screenshot.filename} needs provenance`);
    assert.equal(screenshot.truthStatus, 'real-app-capture');
    countBySize.set(size, (countBySize.get(size) ?? 0) + 1);
    hasModernRequiredSize ||= modernRequiredSizes.has(size);
  }

  for (const [size, count] of countBySize) {
    assert(
      count >= storefront.screenshotPolicy.minimumCount &&
        count <= storefront.screenshotPolicy.maximumCount,
      `${locale.id} ${size} must contain ${storefront.screenshotPolicy.minimumCount}-${storefront.screenshotPolicy.maximumCount} screenshots`,
    );
  }

  assert(
    hasModernRequiredSize,
    `${locale.id} needs at least one accepted 6.9-inch screenshot or 6.5-inch fallback`,
  );
}

console.log('App Store storefront validation passed.');
