import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Keep the record in this package so Turbo's default inputs invalidate the CI
// test cache whenever the decision changes, without workflow configuration.
const record = JSON.parse(
  readFileSync(new URL('../decisions/home-coaching-card-wording.json', import.meta.url), 'utf8'),
);
const momentKeys = [
  'on_track',
  'new_weight_import_receipt',
  'add_a_photo_ask',
  'todays_workout',
  'calm_nothing_to_do',
  'deload_deferral_explanation',
];

// This decision permits status/plan wording only, so reject all outcome claims
// rather than treating an unverified reference to "data" as proof of impact.
const denylist = [
  /\b(?:diagnos\w*|diabet\w*|prediabet\w*|hypertension|high blood pressure|obes(?:e|ity)|osteoporosis|sarcopenia|overtrain(?:ed|ing)|metabolic syndrome|eating disorder|insulin resistan\w*|depression|anxiety|hypothyroidism|hyperthyroidism|sleep apnea|heart disease|cancer)\b/i,
  /\b(?:you (?:have|may have|might have|likely have)|this indicates)\b[^.!?]{0,60}\b(?:disease|disorder|syndrome|condition|injury)\b/i,
  /\b(?:gains?|gained|gaining|guarantee(?:d|s)?|will definitely)\b/i,
  /\b(?:build\w*|built|grow\w*|grew|add\w*|increas\w*|boost\w*|improv\w*)\b[^.!?]{0,40}\b(?:muscle|strength|lean mass|recovery)\b/i,
  /\b(?:los[et]|losing|burn\w*|burnt|shed\w*|drop\w*|reduc\w*)\b[^.!?]{0,40}\b(?:fat|weight|calories|pounds?|lbs?|kg|kilograms?)\b/i,
  /\b(?:stronger|leaner|fitter|more muscular|improved your physique|transformed your body|prevented an injury)\b/i,
];

function recordText(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value && typeof value === 'object') return Object.values(value).map(recordText).join('\n');
  return '';
}

function validateRecord(value: typeof record) {
  for (const field of ['question', 'decision']) {
    assert(typeof value[field] === 'string' && value[field].trim(), `${field} must be non-empty`);
  }
  assert(value.status === 'accepted', 'The wording question must be resolved');
  assert(value.moments && typeof value.moments === 'object', 'moments must be an object');
  assert.deepEqual(Object.keys(value.moments).sort(), [...momentKeys].sort());
  for (const key of momentKeys) {
    assert(
      typeof value.moments[key] === 'string' && value.moments[key].trim(),
      `${key} must be a non-empty string`,
    );
    assert(
      typeof value.show_when?.[key] === 'string' && value.show_when[key].trim(),
      `${key} must state its observation or plan condition`,
    );
  }
  const text = recordText(value)
    .normalize('NFKC')
    .replace(/[’‘]/g, "'")
    .replace(/[-_\s]+/g, ' ');
  for (const phrase of denylist) assert(!phrase.test(text), `Disallowed record wording: ${phrase}`);
}

describe('LYB-302 home coaching card wording decision', () => {
  it('loads the resolved question, all six sentences and their conditions from the record', () => {
    validateRecord(record);
  });

  for (const key of momentKeys) {
    it(`rejects missing, empty and non-string ${key} wording`, () => {
      for (const invalid of [undefined, '', ' \n\t ', null, 42, {}]) {
        const candidate = JSON.parse(JSON.stringify(record));
        if (invalid === undefined) delete candidate.moments[key];
        else candidate.moments[key] = invalid;
        expect(() => validateRecord(candidate)).toThrow();
      }
    });
  }

  it.each([
    'You have diabetes.',
    'You have high blood pressure.',
    "You're insulin resistant.",
    'You may have a medical condition.',
    'Your check-in diagnoses overtraining.',
    'You are obese.',
    'Your results indicate metabolic syndrome.',
    'You gained muscle.',
    'You will build muscle.',
    'This workout boosted your strength.',
    'The deload improved your recovery.',
    'You lost 2 kg of fat.',
    'You burned more calories.',
    "You're getting stronger.",
    'Your saved data proves you are leaner.',
    'Guaranteed results.',
    'YOU HAVE\nDIABETES.',
    'You have an eating-disorder.',
  ])('rejects unsafe record text: %s', (text) => {
    for (const key of momentKeys) {
      const candidate = JSON.parse(JSON.stringify(record));
      candidate.moments[key] = text;
      expect(() => validateRecord(candidate)).toThrow(/Disallowed record wording/);
    }
    // Guard explanatory text as well as the six user-visible lines.
    const candidate = { ...record, decision: text };
    expect(() => validateRecord(candidate)).toThrow(/Disallowed record wording/);
  });
});
