import assert from 'node:assert/strict';
import { URL } from 'node:url';
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

const { endpoints } = logYourBody;
for (const host of Object.values(endpoints.hosts)) {
  assert.equal(new URL(host.url).host, host.host, `${host.url} must match its host`);
}
assert(
  endpoints.deepLinks.applinksHosts.includes(endpoints.hosts.api.host),
  'applinks hosts must include the API host',
);
assert(
  endpoints.auth.clients.ios.redirectUri.startsWith(`${endpoints.deepLinks.scheme}://`),
  'iOS redirect URI must use the registered deep-link scheme',
);
assert(
  endpoints.auth.clients.web.redirectUri.startsWith(endpoints.hosts.api.url),
  'web redirect URI must live on the API host',
);
const allowlistValues = endpoints.allowlist.map((entry) => entry.value);
assert.equal(
  new Set(allowlistValues).size,
  allowlistValues.length,
  'allowlist values must be unique',
);
assert(
  endpoints.allowlist.every((entry) => entry.reason),
  'every allowlist entry needs a reason',
);
