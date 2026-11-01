import {
  ADHERENCE_OFFER_TEMPLATES,
  declineAdherenceOffer,
  renderAdherenceOffer,
  type AdherenceOfferState,
} from './adherence-offers';
import { attendanceChoice, WEEK } from './rolling-schedule-signals';
import { history, source } from './rolling-schedule.testing';
import { MemoryTrainingRecords } from './memory-records.testing';
import { recommendProgram } from './delegated-planning';
import { DELEGATED_POLICY, delegatedSetupSchema } from './delegation-contract';
import { loadTrainingRecords } from './service';
import { TRAINING_CONSENT_VERSION } from './types';

/** Complete attendance windows go through the existing detector, not a second selector. */
function fixture(requested: 5 | 6, counts: number[], hasTravelWeek: boolean | null = false) {
  const input = source();
  const context = input.rollingSchedule!;
  context.attendanceSince = '2026-10-01T00:00:00Z';
  context.asOf = new Date(Date.parse(context.attendanceSince) + counts.length * WEEK).toISOString();
  context.requestedVisitsPerWeek = requested;
  counts.forEach((count, week) => {
    for (let day = 0; day < count; day++)
      history(
        input,
        'A',
        1,
        new Date(Date.parse(context.attendanceSince) + week * WEEK + day * 86400000).toISOString(),
      );
  });
  return {
    proposalId: 'proposal-293',
    choice: attendanceChoice(context, input.logs ?? []),
    hasTravelWeek,
    enabled: true,
    canReverseConsolidation: true,
  };
}

const emptyState = (): AdherenceOfferState => ({ handledProposalIds: [] });

// Independent of the snapshot so updating approved copy cannot bless shaming language.
function deniedCopy(copy: string): boolean {
  const normalized = copy.normalize('NFKC').toLowerCase().replace(/[’‘]/g, "'");
  return /\b(?:fail(?:ed|ing|ure|ures|s)?|ashamed|sham(?:e|ed|ing)|lazy|laziness|guilt\w*|undisciplined|disappoint\w*)\b|\b(?:no excuses|not committed|let(?:ting)? yourself down|falling behind|lost progress|make up for|catch[ -]up|should have)\b/.test(
    normalized,
  );
}

describe('adherence offer payloads (LYB-293)', () => {
  it('locks the approved outbound templates and choices', () => {
    expect(ADHERENCE_OFFER_TEMPLATES).toMatchInlineSnapshot(`
{
  "offer_consolidation": {
    "actions": [
      {
        "id": "decline",
        "label": "Keep 5",
      },
      {
        "id": "review_consolidation",
        "label": "Use 4",
      },
    ],
    "message": "You've completed four sessions a week for three weeks. Consolidate to four days? You can switch back.",
  },
  "review_capacity": {
    "actions": [
      {
        "id": "decline",
        "label": "Keep current plan",
      },
      {
        "id": "review_capacity",
        "label": "Review capacity",
      },
    ],
    "message": "You've completed one session a week. Review what fits your schedule? Your current training volume stays the same.",
  },
}
`);
  });

  it('renders the stable five/four proposal once without a program edit', () => {
    const proposal = fixture(5, [4, 4, 4]);
    const first = renderAdherenceOffer({ ...proposal, state: emptyState() });
    expect(first.outbound).toEqual([
      {
        id: 'adherence-offer:proposal-293',
        proposalId: proposal.proposalId,
        template: 'offer_consolidation',
        ...ADHERENCE_OFFER_TEMPLATES.offer_consolidation,
      },
    ]);
    expect(first.programDiff).toEqual([]);
    expect(renderAdherenceOffer({ ...proposal, state: first.state }).outbound).toEqual([]);
  });

  it('declines without changing the stored five-session request', async () => {
    const records = new MemoryTrainingRecords();
    const program = recommendProgram(
      {
        goal: 'Build muscle',
        goalDate: null,
        experience: 'new',
        sessionsPerWeek: 5,
        minutesPerSession: 60,
        equipment: 'full_gym',
        excludedVariantIds: [],
        limitations: [],
        preferredVariantIds: [],
      },
      4,
    );
    const setup = delegatedSetupSchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      consentVersion: TRAINING_CONSENT_VERSION,
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 5,
      equipment: 'full_gym',
      startedAt: '2026-10-01T00:00:00Z',
      programRevisionId: '22222222-2222-4222-8222-222222222222',
      programPolicyVersion: DELEGATED_POLICY,
      delegated: program,
    });
    await records.push('owner', 'training_feedback', [{ ...setup, record_type: 'program_setup' }]);
    const before = await records.listAll('owner');
    const proposal = fixture(5, [4, 4, 4]);
    const first = renderAdherenceOffer({ ...proposal, state: emptyState() });
    const declined = declineAdherenceOffer(first.state, proposal.proposalId);
    expect(declined.outbound).toEqual([]);
    expect(declined.programDiff).toEqual([]);
    expect(await records.listAll('owner')).toEqual(before);
    expect((await loadTrainingRecords(records, 'owner')).setup?.sessionsPerWeek).toBe(5);
    const restored = JSON.parse(JSON.stringify(declined.state)) as AdherenceOfferState;
    expect(renderAdherenceOffer({ ...proposal, state: restored }).outbound).toEqual([]);
  });

  it.each([
    { counts: [0] },
    { counts: [4] },
    { counts: [5, 5, 0] },
    { counts: [5, 5, 4] },
    { counts: [4, 4] },
  ])('withholds three-week copy for $counts recorded visits', ({ counts }) => {
    const result = renderAdherenceOffer({ ...fixture(5, counts), state: emptyState() });
    expect(result.outbound).toEqual([]);
    expect(result.state).toEqual(emptyState());
    expect(result.programDiff).toEqual([]);
  });

  it.each([true, null])('suppresses a travel or unknown-travel window (%s)', (hasTravelWeek) => {
    const proposal = fixture(5, [4, 4, 4], hasTravelWeek);
    const result = renderAdherenceOffer({ ...proposal, state: emptyState() });
    expect(result.outbound).toEqual([]);
    expect(result.state).toEqual(emptyState());
  });

  it('renders a separate six/one capacity review with an empty program diff', () => {
    const proposal = fixture(6, [1, 1, 1]);
    const result = renderAdherenceOffer({ ...proposal, state: emptyState() });
    expect(result.outbound).toEqual([
      {
        id: 'adherence-offer:proposal-293',
        proposalId: proposal.proposalId,
        template: 'review_capacity',
        ...ADHERENCE_OFFER_TEMPLATES.review_capacity,
      },
    ]);
    expect(result.programDiff).toEqual([]);
    expect(proposal.choice).toMatchObject({
      requestedVisits: 6,
      suggestedVisits: null,
      applied: false,
    });
  });

  it('deduplicates by proposal id across restored state and changed proposal types', () => {
    const first = renderAdherenceOffer({ ...fixture(5, [4, 4, 4]), state: emptyState() });
    const state = JSON.parse(JSON.stringify(first.state)) as AdherenceOfferState;
    const second = renderAdherenceOffer({ ...fixture(6, [1, 1, 1]), state });
    expect(second.outbound).toEqual([]);
    expect(second.state).toEqual(state);
    const next = renderAdherenceOffer({
      ...fixture(6, [1, 1, 1]),
      proposalId: 'another-proposal',
      state,
    });
    expect(next.outbound).toHaveLength(1);
    expect(next.outbound[0].id).toBe('adherence-offer:another-proposal');
    expect(state.handledProposalIds).toEqual(['proposal-293']);
  });

  it('remembers decline before rendering and repeated declines without changing the input state', () => {
    const state = emptyState();
    const proposal = fixture(5, [4, 4, 4]);
    const declined = declineAdherenceOffer(state, proposal.proposalId);
    expect(state).toEqual(emptyState());
    expect(declineAdherenceOffer(declined.state, proposal.proposalId)).toEqual(declined);
    expect(renderAdherenceOffer({ ...proposal, state: declined.state }).outbound).toEqual([]);
  });

  it('defaults off and requires supported consolidation reversal', () => {
    const proposal = fixture(5, [4, 4, 4]);
    for (const overrides of [
      { enabled: undefined },
      { enabled: false },
      { canReverseConsolidation: undefined },
      { canReverseConsolidation: false },
    ]) {
      const result = renderAdherenceOffer({ ...proposal, ...overrides, state: emptyState() });
      expect(result.outbound).toEqual([]);
      expect(result.state).toEqual(emptyState());
    }
    expect(
      renderAdherenceOffer({
        ...fixture(6, [1, 1]),
        canReverseConsolidation: false,
        state: emptyState(),
      }).outbound,
    ).toHaveLength(1);
  });

  it('withholds unsupported or inconsistent choices instead of inventing copy', () => {
    const proposal = fixture(5, [4, 4, 4]);
    const choice = proposal.choice!;
    for (const changed of [
      { ...choice, requestedVisits: 6 },
      { ...choice, suggestedVisits: 3 },
      { ...choice, observedVisitsPerWeek: [4, 3, 4] },
      { ...choice, kind: 'review_capacity' as const },
    ])
      expect(
        renderAdherenceOffer({ ...proposal, choice: changed, state: emptyState() }).outbound,
      ).toEqual([]);
  });

  it('suppresses travel for capacity review too and never consumes an ineligible proposal', () => {
    const proposal = fixture(6, [1, 1], true);
    const suppressed = renderAdherenceOffer({ ...proposal, state: emptyState() });
    expect(suppressed.outbound).toEqual([]);
    expect(suppressed.state).toEqual(emptyState());
    expect(
      renderAdherenceOffer({
        ...proposal,
        hasTravelWeek: false,
        state: suppressed.state,
      }).outbound,
    ).toHaveLength(1);
  });

  it('supports a longer stable run without changing copy and suppresses missing proposal identity', () => {
    const proposal = fixture(5, [4, 4, 4, 4]);
    expect(renderAdherenceOffer({ ...proposal, state: emptyState() }).outbound).toHaveLength(1);
    expect(
      renderAdherenceOffer({ ...proposal, proposalId: ' ', state: emptyState() }).outbound,
    ).toEqual([]);
    expect(declineAdherenceOffer(emptyState(), '')).toEqual({
      state: emptyState(),
      outbound: [],
      programDiff: [],
    });
    expect(renderAdherenceOffer({ ...fixture(6, [1]), state: emptyState() }).outbound).toEqual([]);
  });

  it('does not expose shared mutable copy or mutate prior offer state', () => {
    const state = Object.freeze({ handledProposalIds: Object.freeze([] as string[]) });
    renderAdherenceOffer({ ...fixture(5, [4, 4, 4]), state });
    expect(state).toEqual(emptyState());
    for (const template of Object.values(ADHERENCE_OFFER_TEMPLATES)) {
      expect(Object.isFrozen(template)).toBe(true);
      expect(Object.isFrozen(template.actions)).toBe(true);
      expect(template.actions.every(Object.isFrozen)).toBe(true);
    }
  });

  it.each(Object.values(ADHERENCE_OFFER_TEMPLATES))(
    'rejects shame or failure wording in $message',
    (template) => {
      expect(
        deniedCopy([template.message, ...template.actions.map((action) => action.label)].join(' ')),
      ).toBe(false);
    },
  );

  it.each([
    'You failed your plan.',
    'This is a FAILURE.',
    'Stop being lazy.',
    'You should feel ashamed.',
    'No excuses.',
    'You are undisciplined.',
    'You are not committed.',
    'You are falling behind.',
    'Make up for lost progress.',
    'You should have done more.',
    'Feeling guilty?',
    'You are disappointing.',
  ])('the deny-list catches unsafe replacement copy: %s', (copy) => {
    expect(deniedCopy(copy)).toBe(true);
  });
});
