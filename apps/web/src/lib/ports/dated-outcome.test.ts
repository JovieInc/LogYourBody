import {
  datedOutcomeEditSchema,
  datedOutcomePlanInputs,
  datedOutcomeSchema,
} from './dated-outcome';
import { planningInputsSchema } from '@/lib/training/delegation-contract';

export const outcomeFixture = {
  outcome: { metric: 'body_fat_percentage' as const, targetValue: 20 },
  outcomeDate: '2027-04-01',
  constraints: {
    availability: {
      sessionsPerWeek: 3 as const,
      minutesPerSession: 45,
      equipment: 'dumbbells' as const,
    },
    travel: [{ start: '2027-01-01', end: '2027-01-07' }],
    maintenance: [{ start: '2027-02-01', end: '2027-02-14' }],
  },
};

describe('dated outcome wire and LYB-130 input boundary', () => {
  it('retains target, date and constraints without prescribing or fabricating missing inputs', () => {
    expect(datedOutcomeSchema.parse(outcomeFixture)).toEqual(outcomeFixture);
    const inputs = datedOutcomePlanInputs(outcomeFixture);
    expect(planningInputsSchema.partial().parse(inputs)).toEqual({
      goal: 'body_fat_percentage: 20',
      goalDate: '2027-04-01T00:00:00Z',
      ...outcomeFixture.constraints.availability,
    });
    expect(inputs).not.toHaveProperty('limitations');
    expect(inputs).not.toHaveProperty('experience');
  });

  it.each([
    { ...outcomeFixture, outcomeDate: '2027-02-30' },
    { ...outcomeFixture, outcome: { metric: 'inferred_appearance', targetValue: 20 } },
    { ...outcomeFixture, outcome: { metric: 'weight_kg', targetValue: Infinity } },
    {
      ...outcomeFixture,
      constraints: {
        ...outcomeFixture.constraints,
        travel: [{ start: '2027-02-01', end: '2027-01-01' }],
      },
    },
    {
      ...outcomeFixture,
      constraints: { ...outcomeFixture.constraints, availability: { goal: 'override' } },
    },
    {
      ...outcomeFixture,
      constraints: { ...outcomeFixture.constraints, availability: { sessionsPerWeek: 7 } },
    },
  ])('rejects malformed dates, targets, intervals and unknown constraint fields', (value) => {
    expect(datedOutcomeSchema.safeParse(value).success).toBe(false);
  });

  it('accepts expired dates for review without extending the date', () => {
    const expired = { ...outcomeFixture, outcomeDate: '2020-01-01' };
    expect(datedOutcomeSchema.parse(expired).outcomeDate).toBe('2020-01-01');
  });

  it('requires explicit initial revision and rejects client ownership fields', () => {
    const edit = {
      requestId: '26800000-0000-4000-8000-000000000001',
      previousRevision: null,
      value: outcomeFixture,
    };
    expect(datedOutcomeEditSchema.parse(edit)).toEqual(edit);
    expect(datedOutcomeEditSchema.safeParse({ ...edit, ownerId: 'foreign' }).success).toBe(false);
    expect(
      datedOutcomeEditSchema.safeParse({ requestId: edit.requestId, value: edit.value }).success,
    ).toBe(false);
  });
});
