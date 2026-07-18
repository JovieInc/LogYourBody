import assert from 'node:assert/strict';
import { logYourBody } from '../src/products/logyourbody.mjs';

const featureIds = logYourBody.features.map((feature) => feature.id);
assert.equal(new Set(featureIds).size, featureIds.length, 'feature IDs must be unique');

const planIds = logYourBody.plans.map((plan) => plan.id);
assert.equal(new Set(planIds).size, planIds.length, 'plan IDs must be unique');

for (const plan of logYourBody.plans) {
  for (const featureId of plan.featureIds) {
    assert(featureIds.includes(featureId), `${plan.id} references unknown feature ${featureId}`);
  }
  assert(plan.pricing.monthly.productId.startsWith(logYourBody.identity.bundleId));
  assert(plan.pricing.annual.productId.startsWith(logYourBody.identity.bundleId));
}

for (const option of logYourBody.support.filter((option) => option.public)) {
  assert(option.href, `${option.id} needs a public destination`);
}
