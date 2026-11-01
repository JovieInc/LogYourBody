import { SCHEDULER_CLAIMS, schedulerClaim } from './scheduler-claims';

const assertion =
  /\b(?:proves?|means?|confirms?|guarantees?|certifies|establishes|ensures|shows?|determines?|judges?|judged|indicates?)\b|\b(?:you are|you're) (?:fully )?(?:recovered|ready)\b/;
const recovery = /\b(?:recover\w*|read\w*)\b/;

/** Conservative copy lint, not a natural-language evidence evaluator. The
 * approved snapshot is the allow-list; these independent rules also reject a
 * forbidden claim if someone updates that snapshot alongside unsafe copy. */
const forbiddenClaims: Record<string, readonly RegExp[]> = {
  once_weekly_ineffective: [
    /\b(?:once (?:a |per )?week(?:ly)?|(?:one|1) (?:day|session|visit)s? (?:a|per) week)\b/,
    /\b(?:ineffective|useless|pointless|insufficient|no (?:growth|gains|benefit)|cannot build|can't build|does not work|doesn't work|won't work|too infrequent)\b/,
  ],
  three_days_uniquely_optimal: [
    /\b(?:three|3) (?:days?|times?|sessions?|visits?)\b/,
    /\b(?:uniquely|only|best|optimal|optimum|ideal|perfect)\b/,
  ],
  universal_readiness_clock: [/\b(?:30|thirty) (?:hours?|hrs?|h)\b/, recovery],
  absent_soreness_proves_recovery: [
    /\b(?:no soreness|not (?:being )?sore|aren't sore|absence of (?:muscle )?soreness|absent soreness|soreness absence|soreness (?:is |has )?(?:absent|gone|disappeared|resolved))\b/,
    assertion,
    recovery,
  ],
  duration_alone_judges_recovery: [
    /\b(?:duration alone|duration by itself|(?:session|workout) length alone|(?:only|solely) (?:by |from |on )?(?:(?:session|workout|training) )?(?:duration|length))\b/,
    assertion,
    recovery,
  ],
  universal_ninety_minute_ceiling: [
    /\b(?:(?:90|ninety) (?:minutes?|mins?)|(?:1\.5|one and a half) hours?)\b/,
    /\b(?:never|always|everyone|universal|maximum|must|should|cannot|can't|ceiling|limit(?:ed)? to|all (?:sessions|workouts)|no (?:session|workout))\b/,
  ],
  forty_shoulder_sets_prescription: [
    /\b(?:40|forty)\b/,
    /\bsets?\b/,
    /\b(?:shoulders?|delts?|deltoids?)\b/,
    /\b(?:week|weekly)\b/,
  ],
};

function deniedClaims(sentence: string): string[] {
  const normalized = sentence
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[’‘]/g, "'")
    .replace(/[-‐‑‒–—]/g, ' ')
    .replace(/\b(30|90)(hours?|hrs?|h|minutes?|mins?)\b/g, '$1 $2')
    .replace(/\s+/g, ' ')
    // Explicit uncertainty is allowed; it must not become an assertion match.
    .replace(
      /\b(?:does not|do not|cannot|can't|doesn't|never) (?:prove|mean|confirm|guarantee|certify|establish|ensure|show|determine|judge)\b/g,
      '',
    );
  return Object.entries(forbiddenClaims)
    .filter(([, patterns]) => patterns.every((pattern) => pattern.test(normalized)))
    .map(([claim]) => claim);
}

describe('approved scheduler claims (LYB-292)', () => {
  test('locks the approved default catalog', () => {
    expect(SCHEDULER_CLAIMS).toMatchInlineSnapshot(`
{
  "additional_visit_requires_review": "Review the distribution of your individualized target before adding a visit beyond your agreed frequency.",
  "applied_recovery_reduction": "The applied recovery review reduces your remaining approved work for this trial.",
  "conditional_not_measured": "This proposed schedule is conditional on your current response and does not measure recovery.",
  "conflicting_observations": "Conflicting observations leave readiness uncertain and require review before changing the plan.",
  "continuation_context_requires_review": "Review the partial workout and its visit identity before continuing its remaining work.",
  "direct_and_overlapping_completed_work_requires_review": "Review both direct and overlapping completed work when considering the proposed dose.",
  "earlier_proposed_work_requires_reassessment_after_completion": "Reassess later proposed work after the earlier work is completed and its response is known.",
  "ended": "This workout was ended, and only logged work counts as completed training.",
  "fatigue_limit_reached": "Further sets for this exercise are omitted where the supplied fatigue signal limits productive work.",
  "first_exposure": "Start with the first exposure in your approved rotation.",
  "marginal_benefit_retained": "Retained sets have positive supplied marginal-benefit signals, and their estimated duration does not certify recovery.",
  "marginal_value_exhausted": "Further sets for this exercise are omitted where the supplied marginal-benefit signal is no longer positive.",
  "next_after_last_completion": "Continue the rotation from the last recorded completion.",
  "no_completed_work": "No completed work is recorded in this snapshot, so training history cannot establish readiness.",
  "no_feasible_work_at_this_opportunity": "No remaining approved work fits this opportunity under the current constraints.",
  "no_productive_sets": "No productive sets remain available under the current constraints.",
  "offer_consolidation": "Your recorded attendance supports reviewing fewer visits as a way to distribute your individualized target.",
  "priority_touches_do_not_fit": "The productive priority touches cannot fit your supplied time cap, so this opportunity needs review.",
  "readiness_is_dose_and_context_dependent": "Readiness remains conditional on the proposed dose, completed work, and your current context.",
  "recovery_limit_applied": "The supplied recovery limits constrain retained volume or effort even when more time is available.",
  "remaining_work_is_not_catch_up_debt": "Remaining work calls for a plan review rather than extra work to repay missed visits.",
  "requires_reviewed_move_reduction_or_rest": "Review moving or reducing the remaining work, or resting, within your individualized plan.",
  "review_capacity": "Review how your individualized target can fit your recorded attendance before changing visit frequency.",
  "session_unavailable": "This session remains unavailable while its safety stop or execution pause is active.",
  "shortened": "Your requested time budget was applied while preserving already logged work.",
  "skipped_recent_stimulus": "Another exposure comes first because recent overlapping work falls within your supplied scheduling window.",
  "stale_or_future_observation": "Some observations are stale or future-dated, so current readiness remains uncertain.",
  "time_cap_applied": "Lower-value work is trimmed to fit your supplied time cap while preserving feasible productive priority touches.",
  "unlogged_workout": "Unlogged work leaves uncertainty about the training already completed.",
  "use_explicit_continuation_for_existing_visit": "Continuing this recorded visit requires an explicit continuation of its partial workout.",
  "warmup_and_symptoms_require_reassessment": "Reassess warm-up performance and symptoms because soreness alone cannot establish recovery.",
}
`);
    expect(Object.isFrozen(SCHEDULER_CLAIMS)).toBe(true);
  });

  test.each(Object.entries(SCHEDULER_CLAIMS))(
    '%s resolves to exactly one approved sentence',
    (code, sentence) => {
      expect(schedulerClaim(code)).toBe(sentence);
      expect(sentence).toBe(sentence.trim());
      expect(sentence).toMatch(/^[^.!?]+[.!?]$/);
    },
  );

  test.each(Object.entries(SCHEDULER_CLAIMS))(
    '%s contains no forbidden claim',
    (_code, sentence) => {
      expect(deniedClaims(sentence)).toEqual([]);
    },
  );

  test.each([
    ['once_weekly_ineffective', 'Once-weekly training is inherently ineffective.'],
    ['once_weekly_ineffective', 'Training one day per week is useless for muscle growth.'],
    ['three_days_uniquely_optimal', 'Three days is uniquely optimal.'],
    ['three_days_uniquely_optimal', 'The only ideal frequency is 3 sessions per week.'],
    ['universal_readiness_clock', 'Everyone is recovered after 30 hours.'],
    ['universal_readiness_clock', 'A universal thirty-hour readiness clock applies.'],
    ['absent_soreness_proves_recovery', 'Absent soreness proves recovery.'],
    ['absent_soreness_proves_recovery', 'No soreness means you are fully recovered.'],
    ['absent_soreness_proves_recovery', 'Soreness has disappeared, which confirms readiness.'],
    ['absent_soreness_proves_recovery', 'If you are not sore, you’re fully recovered.'],
    ['duration_alone_judges_recovery', 'Duration alone judges recovery.'],
    ['duration_alone_judges_recovery', 'Session length alone determines readiness.'],
    ['duration_alone_judges_recovery', 'Only workout duration proves recovery.'],
    ['duration_alone_judges_recovery', 'Recovery can be judged solely from session duration.'],
    ['universal_ninety_minute_ceiling', 'A universal 90-minute ceiling applies.'],
    ['universal_ninety_minute_ceiling', 'Everyone must stop training after ninety minutes.'],
    ['universal_ninety_minute_ceiling', 'Sessions should never exceed 1.5 hours.'],
    ['universal_ninety_minute_ceiling', 'All workouts end within 90min.'],
    ['forty_shoulder_sets_prescription', 'Train shoulders with 40 sets per week.'],
    ['forty_shoulder_sets_prescription', 'Your prescription is forty weekly sets for deltoids.'],
  ])('deny-list rejects %s: %s', (claim, sentence) => {
    expect(deniedClaims(sentence)).toContain(claim);
  });

  test.each([
    'Once-weekly training can contribute to an individualized target.',
    'Three visits distribute your approved work across your available opportunities.',
    'No soreness does not prove recovery.',
    'Duration alone cannot establish readiness.',
    'Your supplied time cap is 90 minutes.',
  ])('allows individualized distribution and explicit uncertainty: %s', (sentence) => {
    expect(deniedClaims(sentence)).toEqual([]);
  });

  test.each(['future_reason', '', 'toString', 'constructor', '__proto__'])(
    'rejects unknown code %j',
    (code) => {
      expect(() => schedulerClaim(code)).toThrow('unapproved_scheduler_claim');
    },
  );
});
