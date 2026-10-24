import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { extractAssistantTexts, run, scan, scanClaimText } from './lint-claims.mjs';

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

const webCopyPaths = [
  'apps/web/src/app/launch-landing-copy.ts',
  'apps/web/src/app/waitlist-copy.ts',
  'apps/web/src/app/home-page-copy.ts',
  'apps/web/src/app/page.tsx',
  'apps/web/src/app/layout.tsx',
  ...[
    'about',
    'support',
    'security',
    'privacy',
    'terms',
    'health-disclosure',
    'signup',
    'signin',
  ].map((route) => `apps/web/src/app/${route}/page.tsx`),
  'apps/web/src/app/download/ios/metadata.ts',
  'apps/web/src/components/NewMarketingSection.tsx',
  'apps/web/src/constants/app.ts',
  'apps/web/src/lib/load-legal-docs.ts',
  'packages/product-registry/src/products/logyourbody.mjs',
  'shared/legal/health-disclosure.md',
  'apps/web/content/blog/published.md',
];

for (const file of webCopyPaths) {
  test('blocks prohibited claims in web copy source ' + file, async (t) => {
    const root = await claimsFixture(t, { [file]: `\n${positiveClaim}\n` });
    await assert.rejects(run(root), (error) => {
      assert.ok(error.message.includes(file + ':2'));
      assert.match(error.message, /\[disease-claim\]/);
      assert.match(error.message, /\[regulatory-status-claim\]/);
      assert.match(error.message, /copy owner/i);
      return true;
    });
  });
}

for (const [label, file, content, rule] of [
  [
    'removed trial offer',
    webCopyPaths[0],
    "export const copy = { cta: 'Start your 3-day free trial' };",
    'free-trial-claim',
  ],
  [
    'numeric outcome in JSON-LD',
    'apps/web/src/app/page.tsx',
    "const jsonLd = { description: 'Lose 10 pounds in 30 days' };",
    'quantified-outcome',
  ],
  [
    'removed genetic potential claim',
    'apps/web/src/app/layout.tsx',
    "export const metadata = { description: 'Know your genetic potential' };",
    'genetic-potential-claim',
  ],
]) {
  test('rejects reintroduced ' + label, async (t) => {
    const root = await claimsFixture(t, { [file]: content });
    await assert.rejects(run(root), (error) => {
      assert.ok(error.message.includes(file + ':1 [' + rule + ']'));
      return true;
    });
  });
}

test('allows qualified pricing, measurement examples, and legal disclaimers', async (t) => {
  const root = await claimsFixture(t, {
    [webCopyPaths[0]]: `
      Reference pricing: $9.99 a month or $69.99 a year (USD).
      The App Store confirms your local price, any free trial eligibility, and terms.
      A measured change of 2 kg over 30 days is not a promised result.
      FFMI does not establish your genetic potential or diagnose health.
      This app does not treat diabetes. No guaranteed outcomes.
    `,
    'shared/legal/health-disclosure.md':
      '# No Guarantee of Accuracy\nWe do not guarantee accuracy.',
  });
  await run(root);
});

test('excludes web tests, API prompts, generated outputs, and unpublished blog drafts', async (t) => {
  const root = await claimsFixture(t, {
    'apps/web/src/app/__tests__/copy.ts': positiveClaim,
    'apps/web/src/app/copy.test.ts': positiveClaim,
    'apps/web/src/components/copy.spec.tsx': positiveClaim,
    'apps/web/src/app/api/chat/route.ts': positiveClaim,
    'apps/web/.next/server/app/page.js': positiveClaim,
    'apps/web/content/blog/draft.md': '---\ndraft: true\n---\n' + positiveClaim,
  });
  await run(root);
});

test('web ratchet uses only supplied source and retains complete findings without line numbers', () => {
  const file = webCopyPaths[0];
  const copy = "const cta = 'Start your 3-day free trial';";
  const snapshot = (text) => ({ files: [file], readSource: () => text });
  const findings = scan(snapshot(copy));
  assert.equal(findings.length, 1);
  assert.equal(findings[0].path, file);
  assert.ok(findings[0].key.includes(copy));
  assert.deepEqual(scan(snapshot('\n\n' + copy)), findings);
  assert.equal(scan(snapshot(copy + '\n' + copy)).length, 2);
  assert.notDeepEqual(scan(snapshot(copy.replace('3-day', '7-day'))), findings);
});

test('existing web findings warn, but changed and additional claims block', async (t) => {
  const warnings = [];
  t.mock.method(process.stderr, 'write', (text) => {
    warnings.push(text);
    return true;
  });
  const file = webCopyPaths[0];
  const copy = "const cta = 'Start your 3-day free trial';";
  const findings = scan({ files: [file], readSource: () => copy });
  const root = await claimsFixture(t, {
    [file]: copy,
    'scripts/knowledge/web-claims-baseline.json': JSON.stringify({
      schema: 'lyb.correction-ratchet/v1',
      findings,
    }),
  });
  await run(root);
  assert.match(warnings.join('\n'), /::warning::.*copy owner:.*web-claims-owner-handoff\.md/);
  await writeFile(path.join(root, file), copy + '\n' + copy);
  await assert.rejects(run(root), /\[free-trial-claim\]/);
  await writeFile(path.join(root, file), copy.replace('3-day', '7-day'));
  await assert.rejects(run(root), /\[free-trial-claim\]/);
  await writeFile(path.join(root, file), 'Track your measurements.');
  await assert.rejects(run(root), /Stale web claims baseline/);
});

test('a negated legal heading does not suppress a subsequent guaranteed outcome', () => {
  assert.deepEqual(scanClaimText('No Guarantee of Accuracy.'), []);
  assert.deepEqual(scanClaimText('No guarantee of accuracy. You will lose 10 pounds.'), [
    { rule: 'guaranteed-outcome', line: 1 },
  ]);
});
