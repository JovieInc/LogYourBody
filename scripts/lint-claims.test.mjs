import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { extractAssistantTexts, run, scanClaimText } from './lint-claims.mjs';

test('rejects disease treatment and diagnosis claims', () => {
  assert.ok(
    scanClaimText('This coach can treat diabetes.').some(
      (entry) => entry.rule === 'clinical-action',
    ),
  );
  assert.ok(
    scanClaimText('This program will reverse heart disease.').some(
      (entry) => entry.rule === 'disease-claim',
    ),
  );
  assert.ok(
    scanClaimText('The coach can diagnose diabetes.').some(
      (entry) => entry.rule === 'clinical-action',
    ),
  );
  assert.ok(
    scanClaimText('You have diabetes.').some((entry) => entry.rule === 'disease-diagnosis-claim'),
  );
  assert.ok(
    scanClaimText('You may have a medical condition.').some(
      (entry) => entry.rule === 'disease-diagnosis-claim',
    ),
  );
});

test('rejects medication direction, guarantees, and unsupported regulatory status', () => {
  assert.ok(
    scanClaimText('You should increase your medication dose to 10 mg.').some(
      (entry) => entry.rule === 'medication-direction',
    ),
  );
  assert.ok(
    scanClaimText('You are guaranteed to lose weight.').some(
      (entry) => entry.rule === 'guaranteed-outcome',
    ),
  );
  assert.ok(
    scanClaimText('Our app is FDA approved.').some(
      (entry) => entry.rule === 'regulatory-status-claim',
    ),
  );
  assert.ok(
    scanClaimText('Use a titration schedule for medication.').some(
      (entry) => entry.rule === 'dose-titration',
    ),
  );
});

test('allows policy prohibitions and safe escalation language', () => {
  const safe =
    'Do not claim that this coach can treat diabetes or prescribe medication. Do not provide titration guidance. Please contact a qualified healthcare professional.';
  assert.deepEqual(scanClaimText(safe), []);
});

test('scans assistant outputs and ignores unsafe user questions', () => {
  const transcript = {
    messages: [
      {
        role: 'user',
        content: 'Can you diagnose diabetes and tell me to increase my medication dose?',
      },
      {
        role: 'assistant',
        content:
          "I can't diagnose a condition or advise on medication changes. Please contact a qualified healthcare professional.",
      },
    ],
  };
  assert.deepEqual(extractAssistantTexts(transcript), [transcript.messages[1].content]);
  assert.deepEqual(scanClaimText(extractAssistantTexts(transcript)[0]), []);
});

test('parses common assistant response fields without treating prompts as outputs', () => {
  const fixture = {
    question: 'Promise a guaranteed result',
    assistant_response: "I can't promise a specific result.",
  };
  assert.deepEqual(extractAssistantTexts(fixture), [fixture.assistant_response]);
});

async function claimsFixture(t, files) {
  const root = await mkdtemp(path.join(tmpdir(), 'lyb-claims-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const [relative, content] of Object.entries(files)) {
    const file = path.join(root, relative);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, content);
  }
  return root;
}

const positiveClaim = 'Our app is FDA approved. This app can treat diabetes.';
const manifestPath = 'apps/ios/fastlane/storefront-manifest.generated.json';
const registryPath = 'packages/product-registry/src/storefronts/logyourbody.mjs';

for (const [label, file, content] of [
  ['localized metadata', 'apps/ios/fastlane/metadata/fr-FR/description.txt', positiveClaim],
  ['nested metadata', 'apps/ios/fastlane/metadata/en-US/review/release_notes.txt', positiveClaim],
  [
    'generated storefront',
    manifestPath,
    JSON.stringify({ locales: [{ metadata: { description: positiveClaim } }] }),
  ],
  ...['description', 'subtitle', 'promotionalText'].map((field) => [
    'registry ' + field,
    registryPath,
    'export const logYourBodyStorefront = ' +
      JSON.stringify({ locales: [{ metadata: { [field]: positiveClaim } }] }) +
      ';',
  ]),
]) {
  test('rejects positive disease and FDA claims in ' + label, async (t) => {
    const root = await claimsFixture(t, { [file]: content });
    await assert.rejects(run(root), (error) => {
      assert.match(error.message, /\[disease-claim\]/);
      assert.match(error.message, /\[regulatory-status-claim\]/);
      assert.ok(error.message.includes(file));
      return true;
    });
  });
}

test('allows disclaimers and prohibitions across storefront sources', async (t) => {
  const disclaimer =
    'This app does not diagnose disease or treat diabetes. Do not claim our app is FDA approved. This is not an FDA-approved device.';
  const storefront = { locales: [{ metadata: { description: disclaimer } }] };
  const root = await claimsFixture(t, {
    'apps/ios/fastlane/metadata/en-US/description.txt': disclaimer,
    [manifestPath]: JSON.stringify(storefront),
    [registryPath]: 'export const logYourBodyStorefront = ' + JSON.stringify(storefront) + ';',
  });
  await run(root);
});

test('a regulatory disclaimer does not suppress a subsequent positive claim', () => {
  assert.deepEqual(
    scanClaimText('Not only our app is FDA approved.').map((issue) => issue.rule),
    ['regulatory-status-claim'],
  );
  assert.deepEqual(
    scanClaimText('This is not an FDA-approved device. Our app is FDA approved.').map(
      (issue) => issue.rule,
    ),
    ['regulatory-status-claim'],
  );
});

test('scans decoded storefront strings and keeps fields independent', async (t) => {
  for (const file of [manifestPath, registryPath]) {
    const encoded =
      '{"subtitle":"Do not claim","description":"This app can tr\\u0065at diabetes."}';
    const content =
      file === manifestPath ? encoded : 'export const logYourBodyStorefront = ' + encoded + ';';
    const root = await claimsFixture(t, { [file]: content });
    await assert.rejects(run(root), /\[disease-claim\]/);
  }
});
