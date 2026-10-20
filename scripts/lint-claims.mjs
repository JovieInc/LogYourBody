import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

function isNegated(text, index) {
  const prefix = text.slice(Math.max(0, index - 80), index);
  return /\b(?:do not|don't|does not|doesn't|did not|didn't|must not|should not|cannot|can't|never|avoid|without)\s+(?:[\w'-]+\s+){0,5}$/i.test(
    prefix,
  );
}

export function scanClaimText(text) {
  const violations = [];
  for (const rule of RULES) {
    rule.pattern.lastIndex = 0;
    for (const match of text.matchAll(rule.pattern)) {
      if (isNegated(text, match.index)) continue;
      if (rule.requiresMedicationContext && !rule.requiresMedicationContext.test(text)) continue;
      const line = text.slice(0, match.index).split('\n').length;
      violations.push({ rule: rule.id, line });
    }
  }
  return violations;
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

  if (violations.length)
    throw new Error('Claims lint failed:\n' + [...new Set(violations)].join('\n'));
  process.stdout.write(
    'Claims lint passed; scanned ' +
      skillFiles.length +
      ' compiled skills, ' +
      instructionFiles.length +
      ' compiled instructions, and ' +
      transcriptCount +
      ' assistant eval outputs.\n',
  );
}

if (process.argv[1] && import.meta.url === new URL(process.argv[1], 'file:').href) {
  run().catch((error) => {
    process.stderr.write((error instanceof Error ? error.message : String(error)) + '\n');
    process.exitCode = 1;
  });
}
