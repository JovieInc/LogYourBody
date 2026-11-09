import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Decisions live in this package so a change invalidates Turbo's existing CI
// test cache. This slice records the policy only; it does not select movements.
const policyPath = 'muscle-priority-axial-fatigue-steering.json';
const policyKind = 'muscle_priority_axial_fatigue_steering';
const decisionsDirectory = new URL('../decisions/', import.meta.url);

const policy = {
  id: 'LYB-276',
  parent: 'LYB-107',
  kind: policyKind,
  status: 'accepted',
  approvalBasis: 'ships-if-unanswered',
  recordedOn: '2026-11-09',
  question:
    'May prioritize-muscle, minimize-axial-fatigue, or a pain boundary cap or exclude saved-program movements, or may it only annotate a preference?',
  value: {
    effect: 'cap_or_exclude_matching_movements',
    substitutionPath: 'LYB-113',
    preferenceOnly: false,
    storeUserWords: true,
    extraClaim: false,
    cases: ['prioritize_muscle', 'minimize_axial_fatigue', 'pain_boundary'],
  },
  boundaries:
    "Decision record only. Matching movements may be capped or excluded through the existing substitution path. The user's words are stored. Deterministic loads stay on LYB-37. Plan documents stay on LYB-119. Bounded hold and adapt stay on LYB-128. Scenario execution stays on LYB-45. This record does not compute loads or select a movement list.",
};

type Carrier = { path: string; value: unknown };

const forbiddenText = [
  {
    kind: 'diagnosis',
    pattern:
      /\b(?:diagnos\w*|diabetes|hypertension|high blood pressure|obesity|obese|osteoporosis|sarcopenia|metabolic syndrome|eating disorder|arthritis|cancer|depression|anxiety|sleep apnea|heart disease|pcos|polycystic ovary syndrome|hypothyroidism|hyperthyroidism|herniated disc|sciatica)\b/i,
  },
  {
    kind: 'treatment',
    pattern:
      /\b(?:treat(?:ment|ing|ed|s)?|therap\w*|rehabilitat\w*|cures?|curing|prescri(?:be|bing|ption))\b/i,
  },
  {
    kind: 'medication',
    pattern:
      /\b(?:medications?|medicines?|drugs?|dosages?|glp\s*1|semaglutide|tirzepatide|ozempic|wegovy|mounjaro|zepbound|insulin)\b/i,
  },
  {
    kind: 'body-composition',
    pattern: /\b(?:body composition|body fat|lean mass|physique|recomp\w*)\b/i,
  },
  {
    kind: 'recovery-outcome',
    pattern:
      /\b(?:recovery outcome|recovered|faster recovery|full recovery|you will recover|healed|pain free)\b/i,
  },
  {
    kind: 'trademark',
    pattern:
      /\b(?:renaissance periodization|rp strength|menno henselmans|bayesian bodybuilding|mike israetel|jeff nippard|starting strength|athlean\s*x|bigger leaner stronger|stronglifts|juggernautai|5\s*\/\s*3\s*\/\s*1)\b/i,
  },
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stable(value: unknown): string {
  return JSON.stringify(sortValue(value));
}

function sortValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortValue);
  if (!isRecord(value)) return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortValue(value[key])]),
  );
}

function decisionValue(carrier: Carrier): unknown {
  return isRecord(carrier.value) && 'value' in carrier.value ? carrier.value.value : undefined;
}

function isCarrier(path: string, value: unknown): boolean {
  if (path === policyPath || path.endsWith(`/${policyPath}`)) return true;
  if (!isRecord(value)) return valueIncludesPolicy(typeof value === 'string' ? value : '');
  return value.id === policy.id || value.kind === policyKind;
}

function valueIncludesPolicy(text: string): boolean {
  return text.includes(policy.id) || text.includes(policyKind);
}

function policyText(value: unknown): string {
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return value.map(policyText).join('\n');
  if (!isRecord(value)) return '';
  return Object.entries(value)
    .map(([key, entry]) => `${key}\n${policyText(entry)}`)
    .join('\n');
}

function normalize(text: string): string {
  return text
    .normalize('NFKC')
    .replace(/([a-z\d])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .replace(/[’‘]/g, "'")
    .replace(/\s+/g, ' ')
    .toLowerCase();
}

function assertPolicyText(value: unknown) {
  const text = normalize(policyText(value));
  for (const rule of forbiddenText) {
    if (rule.pattern.test(text)) throw new Error(`forbidden policy text: ${rule.kind}`);
  }
}

function assertSinglePolicy(carriers: Carrier[]) {
  if (carriers.length === 0) throw new Error('missing policy value');
  const distinct = new Set(carriers.map((carrier) => stable(decisionValue(carrier))));
  if (distinct.size > 1) throw new Error('divergent policy value');
  if (carriers.length !== 1) throw new Error('exactly one policy value is required');
  const carrier = carriers[0];
  assert.equal(carrier.path, policyPath);
  assert.deepEqual(carrier.value, policy);
  assertPolicyText(carrier.value);
  return carrier.value;
}

function loadCarriers(): Carrier[] {
  return readdirSync(decisionsDirectory, { recursive: true }).flatMap((entry) => {
    if (typeof entry !== 'string') return [];
    const url = new URL(entry, decisionsDirectory);
    if (statSync(url).isDirectory()) return [];
    const path = entry.split(/[\\/]/).join('/');
    if (path.endsWith('.json')) {
      const value: unknown = JSON.parse(readFileSync(url, 'utf8'));
      return isCarrier(path, value) ? [{ path, value }] : [];
    }
    const text = readFileSync(url, 'utf8');
    return valueIncludesPolicy(text) ? [{ path, value: text }] : [];
  });
}

const records = loadCarriers();

describe('muscle-priority and axial-fatigue steering policy (LYB-276)', () => {
  it('reads the one accepted policy value', () => {
    expect(assertSinglePolicy(records)).toEqual(policy);
  });

  it('fails when the policy is missing or a second value diverges', () => {
    const carrier = { path: policyPath, value: policy };
    const preference = {
      path: 'preference-only.json',
      value: {
        ...policy,
        value: { ...policy.value, preferenceOnly: true, effect: 'annotate_preference' },
      },
    };
    expect(() => assertSinglePolicy([])).toThrow(/missing policy value/);
    expect(() => assertSinglePolicy([carrier, preference])).toThrow(/divergent policy value/);
    expect(() => assertSinglePolicy([carrier, { ...carrier, path: 'copy.json' }])).toThrow(
      /exactly one policy value is required/,
    );
    expect(() => assertSinglePolicy([{ ...carrier, path: 'copy.json' }])).toThrow();
  });

  it.each([
    ['diagnosis', 'diagnosed with diabetes'],
    ['treatment', 'a treatment plan'],
    ['medication', 'Ozempic dose'],
    ['body-composition', 'body-composition'],
    ['body-composition', 'body_composition'],
    ['body-composition', 'bodyComposition'],
    ['recovery-outcome', 'recovery-outcome'],
    ['recovery-outcome', 'recovery_outcome'],
    ['recovery-outcome', 'faster recovery'],
    ['trademark', 'Renaissance Periodization'],
    ['trademark', 'RP Strength'],
  ])('fails when policy text includes a %s string (%s)', (kind, sample) => {
    const candidate = { ...policy, boundaries: `${policy.boundaries} ${sample}` };
    expect(() => assertPolicyText(candidate)).toThrow(`forbidden policy text: ${kind}`);
    expect(() => assertSinglePolicy([{ path: policyPath, value: candidate }])).toThrow();
  });
});
