import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DISEASES =
  '(?:diabetes|obesity|hypertension|high blood pressure|heart disease|cardiovascular disease|chronic kidney disease|kidney disease|heart failure|stroke|cancer|depression|anxiety|arthritis|sleep apnea|eating disorder|polycystic ovary syndrome|PCOS|hypothyroidism|hyperthyroidism|osteoporosis|metabolic syndrome|medical condition|health condition|condition|disease)';
const MEDICATIONS =
  '(?:medication|medicine|drug|dose|dosage|prescription|GLP[- ]?1|semaglutide|tirzepatide|Ozempic|Wegovy|Mounjaro|Zepbound)';

const RULES = [
  {
    id: 'clinical-action',
    pattern: new RegExp(
      '\\b(?:i|we|our coach|our app|our product|this coach|this app|this product|the coach)\\s+(?:can|will|does|may|might|could|should)\\s+(?:help you\\s+to\\s+)?(?:treat|cure|diagnose|prescribe)\\b',
      'gi',
    ),
  },
  {
    id: 'disease-claim',
    pattern: new RegExp(
      '\\b(?:prevent|prevents|preventing|cure|cures|curing|treat|treats|treating|diagnose|diagnoses|diagnosing|detect|detects|detecting|reverse|reverses|reversing|manage|manages|managing|lower|lowers|lowering|reduce|reduces|reducing|improve|improves|improving|control|controls|controlling)\\s+(?:(?:the|your|a|an)\\s+)?(?:risk of\\s+)?' +
        DISEASES +
        '\\b',
      'gi',
    ),
  },
  {
    id: 'disease-diagnosis-claim',
    pattern: new RegExp(
      '\\b(?:you (?:have|may have|might have|likely have)|this means you have|this indicates you have|you are diagnosed with)\\s+(?:(?:a|an)\\s+)?' +
        DISEASES +
        '\\b',
      'gi',
    ),
  },
  {
    id: 'medication-direction',
    pattern: new RegExp(
      '\\b(?:you should|you need to|i recommend|we recommend|take|start|stop|increase|decrease|adjust|change|titrate)\\s+(?:(?:taking|using)\\s+)?(?:(?:your|the|a|an)\\s+)?' +
        MEDICATIONS +
        '\\b',
      'gi',
    ),
  },
  {
    id: 'medication-amount',
    pattern: new RegExp('\\b\\d+(?:\\.\\d+)?\\s*(?:mg|mcg|µg|ml)\\b', 'gi'),
    requiresMedicationContext: new RegExp(MEDICATIONS, 'i'),
  },
  {
    id: 'dose-titration',
    pattern: /\b(?:titrate(?:d|s|ing)?|titration)\b/gi,
  },
  {
    id: 'guaranteed-outcome',
    pattern:
      /\b(?:guarantee(?:d|s)?|will definitely|you will (?:lose|gain|build|reach|achieve))\b/gi,
  },
  {
    id: 'regulatory-status-claim',
    pattern:
      /\b(?:we|our (?:coach|app|product)|this (?:coach|app|product)|the coach)\s+(?:is|has been)\s+(?:FDA[- ]?)?(?:approved|cleared|authorized|exempt)\b|\bFDA[- ]?(?:approved|cleared|authorized)\s+(?:coach|app|product|device|software|tool)\b/gi,
  },
];

// Marketing-audit regressions require copy-owner review, even without an
// explicit guarantee. Keep these rules off assistant/evidence transcripts.
const WEB_RULES = [
  ...RULES,
  { id: 'free-trial-claim', pattern: /\bfree trial\b(?!\s+eligibility)|\bdays?\s+free\b/gi },
  { id: 'genetic-potential-claim', pattern: /\bgenetic potential\b/gi },
  {
    id: 'quantified-outcome',
    pattern:
      /\b(?:lose|lost|gain|gained|drop|dropped|build|built|burn|burned)\s+(?:up to\s+)?\d+(?:\.\d+)?\s*(?:%|(?:pounds?|lbs?|kg|kilograms?|inches?|cm)\b)/gi,
  },
];
const WEB_BASELINE = 'scripts/knowledge/web-claims-baseline.json';
const WEB_ROOTS = [
  'apps/web/src/app',
  'apps/web/src/components',
  'apps/web/src/constants',
  'apps/web/src/lib',
  'apps/web/content/blog',
  'shared/legal',
  'packages/product-registry/src/products',
];

function isNegated(text, index) {
  const prefix = text.slice(Math.max(0, index - 80), index);
  return (
    /\b(?:not|no)\s+(?:(?:a|an|the)\s+)?$/i.test(prefix) ||
    /\b(?:do not|don't|does not|doesn't|did not|didn't|must not|should not|cannot|can't|never|avoid|without)\s+(?:[\w'-]+\s+){0,5}$/i.test(
      prefix,
    )
  );
}

function claimIssues(text, rules) {
  const violations = [];
  for (const rule of rules) {
    rule.pattern.lastIndex = 0;
    for (const match of text.matchAll(rule.pattern)) {
      if (isNegated(text, match.index)) continue;
      if (rule.requiresMedicationContext && !rule.requiresMedicationContext.test(text)) continue;
      const line = text.slice(0, match.index).split('\n').length;
      violations.push({
        rule: rule.id,
        line,
        index: match.index,
        end: match.index + match[0].length,
      });
    }
  }
  return violations;
}

export function scanClaimText(text) {
  return claimIssues(text, RULES).map(({ rule, line }) => ({ rule, line }));
}

// Variant annotations are setup descriptions, never clinical assurances or
// universal loading claims. Keep these stricter rules scoped to the catalog.
const EXERCISE_RULES = [
  {
    id: 'exercise-medical-claim',
    pattern:
      /\b(?:treat(?:s|ment|ing)?|cur(?:e[sd]?|ing)|diagnos\w*|heal\w*|rehabilitat\w*|therapeutic)\b|\b(?:prevent\w*|reliev\w*|eliminat\w*|reduc\w*|fix\w*)\s+(?:(?:your|the|joint|back|shoulder|knee|risk of)\s+){0,3}(?:pain|injur\w*|discomfort)\b|\b(?:pain|injury|risk)\s+free\b|\bsafe\s+for\s+(?:(?:your|the)\s+)?(?:back|spine|joints|knees|shoulders)\b/gi,
  },
  {
    id: 'zero-axial-load',
    pattern:
      /\b(?:zero|no|0)\s+(?:(?:axial|spinal|trunk|back)\s+){1,2}(?:load(?:ing)?|fatigue|demand|stress)\b|\b(?:axial|spinal|trunk)\s+(?:load|fatigue|stress)\s+(?:is\s+)?(?:zero|0|free)\b|\btrunk\s+carries\s+nothing\b/gi,
  },
  {
    id: 'numeric-sfr',
    pattern:
      /\b(?:sfr|stimulus\s+to\s+fatigue(?:\s+ratio)?)(?:\s+(?:score|ratio|is|of))?\s*[:=]?\s*\d|\b\d+(?:\.\d+)?(?:\s*\/\s*\d+)?\s+(?:sfr|stimulus\s+to\s+fatigue)\b/gi,
  },
];

export function scanExerciseVariantText(text) {
  // Also inspect snake_case and hyphenated tags as readable words.
  const normalized = text.replace(/[_-]+/g, ' ');
  return [
    ...scanClaimText(text),
    ...claimIssues(normalized, EXERCISE_RULES).map(({ rule, line }) => ({ rule, line })),
  ];
}

function isWebCopyFile(file) {
  if (
    /\/(?:__tests__|__fixtures__|fixtures)\//.test(file) ||
    /\.(?:test|spec|stories|example)\./.test(file) ||
    file.startsWith('apps/web/src/app/api/')
  )
    return false;
  return (
    /^apps\/web\/src\/(?:app|components|constants)\/.*\.(?:[cm]?[jt]sx?|mdx?)$/.test(file) ||
    file === 'apps/web/src/lib/load-legal-docs.ts' ||
    /^apps\/web\/content\/blog\/.*\.md$/.test(file) ||
    /^shared\/legal\/(?:privacy-policy|terms-of-service|health-disclosure|consumer-health-data-policy)\.md$/.test(file) ||
    file === 'packages/product-registry/src/products/logyourbody.mjs'
  );
}

function webFindings({ files, readSource }) {
  return files.filter(isWebCopyFile).flatMap((file) => {
    const text = readSource(file);
    if (file.startsWith('apps/web/content/blog/')) {
      const frontmatter = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
      if (frontmatter && /^draft:\s*true\s*$/m.test(frontmatter[1])) return [];
    }
    return claimIssues(text, WEB_RULES).map(({ rule, line, index, end }) => {
      const start = text.lastIndexOf('\n', index - 1) + 1;
      const nextLine = text.indexOf('\n', end);
      const statement = text
        .slice(start, nextLine < 0 ? text.length : nextLine)
        .trim()
        .replace(/\s+/g, ' ');
      return { path: file, key: '[' + rule + '] ' + statement, rule, line };
    });
  });
}

// The correction ratchet calls this on both immutable base and working-tree
// snapshots before dependencies are installed. Never read/import app code here.
export function scan(snapshot) {
  return webFindings(snapshot).map(({ path, key }) => ({ path, key }));
}

function textValue(value) {
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return value.map(textValue).filter(Boolean).join('\n');
  if (value && typeof value === 'object') {
    if (typeof value.text === 'string') return value.text;
    if (typeof value.content === 'string') return value.content;
  }
  return '';
}

export function extractAssistantTexts(value, results = []) {
  if (Array.isArray(value)) {
    for (const item of value) extractAssistantTexts(item, results);
    return results;
  }
  if (!value || typeof value !== 'object') return results;

  const role = typeof value.role === 'string' ? value.role.toLowerCase() : '';
  if (role === 'assistant' || role === 'coach') {
    for (const key of ['content', 'text', 'response', 'output']) {
      const found = textValue(value[key]);
      if (found) results.push(found);
    }
    return results;
  }

  for (const [key, child] of Object.entries(value)) {
    if (
      [
        'assistant_response',
        'assistantResponse',
        'final_answer',
        'finalAnswer',
        'model_output',
        'modelOutput',
      ].includes(key)
    ) {
      const found = textValue(child);
      if (found) results.push(found);
    } else if (key !== 'role' && key !== 'question' && key !== 'user_prompt' && key !== 'prompt') {
      extractAssistantTexts(child, results);
    }
  }
  return results;
}

async function filesUnder(directory) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error?.code === 'ENOENT') return [];
    throw error;
  }
  const result = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...(await filesUnder(full)));
    else if (entry.isFile()) result.push(full);
  }
  return result;
}

function markdownAssistantTexts(markdown) {
  const results = [];
  const marker =
    /(?:^|\n)\s*(?:assistant|coach)\s*:\s*([\s\S]*?)(?=\n\s*(?:assistant|coach|user|human)\s*:|$)/gim;
  for (const match of markdown.matchAll(marker)) if (match[1].trim()) results.push(match[1].trim());
  return results;
}

async function evalTexts(file) {
  const content = await readFile(file, 'utf8');
  if (file.endsWith('.jsonl')) {
    return content
      .split(/\r?\n/)
      .filter(Boolean)
      .flatMap((line) => extractAssistantTexts(JSON.parse(line)));
  }
  if (file.endsWith('.json')) return extractAssistantTexts(JSON.parse(content));
  if (file.endsWith('.md')) return markdownAssistantTexts(content);
  return [];
}

function stringFields(value, field = '$') {
  if (typeof value === 'string') return [{ field, text: value }];
  if (!value || typeof value !== 'object') return [];
  return Object.entries(value).flatMap(([key, child]) => stringFields(child, field + '.' + key));
}

async function storefrontTexts(root) {
  const metadataFiles = (await filesUnder(path.join(root, 'apps/ios/fastlane/metadata'))).filter(
    (file) => /\.(?:txt|md)$/.test(file),
  );
  const sources = await Promise.all(
    metadataFiles.map(async (file) => ({
      file,
      field: '',
      text: await readFile(file, 'utf8'),
    })),
  );
  for (const relative of [
    'apps/ios/fastlane/storefront-manifest.generated.json',
    'packages/product-registry/src/storefronts/logyourbody.mjs',
  ]) {
    const file = path.join(root, relative);
    let content;
    try {
      content = await readFile(file, 'utf8');
    } catch (error) {
      if (error?.code === 'ENOENT') continue;
      throw error;
    }
    // Scan the actual string values, independently, so escapes and neighboring
    // disclaimer fields cannot conceal a claim in rendered listing copy.
    const value = file.endsWith('.json')
      ? JSON.parse(content)
      : (await import(pathToFileURL(file).href)).logYourBodyStorefront;
    if (!value || typeof value !== 'object') throw new Error('Invalid storefront: ' + relative);
    sources.push(...stringFields(value).map((source) => ({ file, ...source })));
  }
  return sources;
}

export async function run(root = ROOT) {
  const skillRoots = [path.join(root, 'dist', 'skills'), path.join(root, 'agent', 'skills')];
  const instructionRoots = [
    path.join(root, 'dist', 'instructions'),
    path.join(root, 'agent', 'instructions'),
  ];
  const skillFiles = (await Promise.all(skillRoots.map(filesUnder)))
    .flat()
    .filter((file) => file.endsWith('.md'));
  const instructionFiles = (await Promise.all(instructionRoots.map(filesUnder)))
    .flat()
    .filter((file) => file.endsWith('.md'));
  const evalFiles = (await filesUnder(path.join(root, 'evals'))).filter((file) =>
    /\.(?:json|jsonl|md)$/.test(file),
  );
  const violations = [];

  for (const file of [...skillFiles, ...instructionFiles]) {
    const text = await readFile(file, 'utf8');
    for (const issue of scanClaimText(text))
      violations.push(path.relative(root, file) + ':' + issue.line + ' [' + issue.rule + ']');
  }
  let transcriptCount = 0;
  for (const file of evalFiles) {
    const texts = await evalTexts(file);
    transcriptCount += texts.length;
    for (const text of texts) {
      for (const issue of scanClaimText(text))
        violations.push(path.relative(root, file) + ':assistant-output [' + issue.rule + ']');
    }
  }

  const storefrontSources = await storefrontTexts(root);
  for (const { file, field, text } of storefrontSources) {
    for (const issue of scanClaimText(text))
      violations.push(
        path.relative(root, file) +
          (field ? ':' + field : '') +
          ':' +
          issue.line +
          ' [' +
          issue.rule +
          ']',
      );
  }

  const variantSeedPath = 'apps/web/src/lib/training/catalog-variant-seed.json';
  let variantFields = [];
  try {
    const seed = JSON.parse(await readFile(path.join(root, variantSeedPath), 'utf8'));
    variantFields = stringFields(seed);
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  for (const { field, text } of variantFields) {
    for (const issue of scanExerciseVariantText(text))
      violations.push(variantSeedPath + ':' + field + ' [' + issue.rule + ']');
  }

  const webFiles = (
    await Promise.all(WEB_ROOTS.map((directory) => filesUnder(path.join(root, directory))))
  )
    .flat()
    .map((file) => path.relative(root, file).split(path.sep).join('/'))
    .filter(isWebCopyFile);
  const webSources = new Map(
    await Promise.all(
      webFiles.map(async (file) => [file, await readFile(path.join(root, file), 'utf8')]),
    ),
  );
  const findings = webFindings({ files: webFiles, readSource: (file) => webSources.get(file) });
  let baseline = { schema: 'lyb.correction-ratchet/v1', findings: [] };
  try {
    baseline = JSON.parse(await readFile(path.join(root, WEB_BASELINE), 'utf8'));
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  if (baseline.schema !== 'lyb.correction-ratchet/v1' || !Array.isArray(baseline.findings))
    throw new Error('Invalid web claims baseline');
  const allowed = new Map();
  for (const finding of baseline.findings) {
    if (
      Object.keys(finding).sort().join(',') !== 'key,path' ||
      typeof finding.path !== 'string' ||
      typeof finding.key !== 'string'
    )
      throw new Error('Invalid web claims baseline finding');
    const key = JSON.stringify([finding.path, finding.key]);
    allowed.set(key, (allowed.get(key) ?? 0) + 1);
  }
  for (const finding of findings) {
    const key = JSON.stringify([finding.path, finding.key]);
    const location = finding.path + ':' + finding.line + ' [' + finding.rule + ']';
    if (allowed.get(key) > 0) {
      allowed.set(key, allowed.get(key) - 1);
      process.stderr.write(
        '::warning::Existing web claim ' +
          location +
          '; copy owner: docs/compliance/web-claims-owner-handoff.md\n',
      );
    } else violations.push(location);
  }
  if ([...allowed.values()].some((count) => count > 0))
    violations.push('Stale web claims baseline; remove resolved findings from ' + WEB_BASELINE);

  if (violations.length)
    throw new Error(
      'Claims lint failed:\n' +
        [...new Set(violations)].join('\n') +
        '\nRoute web findings to the copy owner via docs/compliance/web-claims-owner-handoff.md; do not rewrite copy as part of lint maintenance.',
    );
  process.stdout.write(
    'Claims lint passed; scanned ' +
      skillFiles.length +
      ' compiled skills, ' +
      instructionFiles.length +
      ' compiled instructions, and ' +
      transcriptCount +
      ' assistant eval outputs, and ' +
      storefrontSources.length +
      ' storefront text fields/files, ' +
      variantFields.length +
      ' exercise variant text fields, and ' +
      webFiles.length +
      ' web copy sources.\n',
  );
}

if (process.argv[1] && import.meta.url === new URL(process.argv[1], 'file:').href) {
  run().catch((error) => {
    process.stderr.write((error instanceof Error ? error.message : String(error)) + '\n');
    process.exitCode = 1;
  });
}
