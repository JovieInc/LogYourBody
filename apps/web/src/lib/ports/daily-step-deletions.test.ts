/** @jest-environment node */

import { isValidDailyStepDeletion, type DailyStepDeletionInput } from './daily-step-deletions';

const input = (start: string, end: string, zone = 'UTC', date = start): DailyStepDeletionInput => ({
  record: { id: 'a1020304-1111-4111-8111-123456789abc', date, notes: 'preserved note' },
  day_start: start,
  day_end: end,
  time_zone: zone,
});

describe('daily step deletion calendar envelope', () => {
  it('rejects either partial occurrence and the discontinuous whole interval of a midnight rollback date', () => {
    // St Johns entered Nov1 for one minute, returned to Oct31, then entered Nov1 again.
    const zone = 'America/St_Johns';
    for (const [start, end] of [
      ['2009-11-01T02:30:00Z', '2009-11-01T02:31:00Z'],
      ['2009-11-01T03:30:00Z', '2009-11-02T03:30:00Z'],
      ['2009-11-01T02:30:00Z', '2009-11-02T03:30:00Z'],
    ]) {
      expect(isValidDailyStepDeletion(input(start!, end!, zone))).toBe(false);
    }
  });

  it.each([
    ['UTC', '2026-03-08T00:00:00Z', '2026-03-09T00:00:00Z'],
    ['America/Los_Angeles', '2026-03-08T08:00:00Z', '2026-03-09T07:00:00Z'],
    ['America/Los_Angeles', '2026-11-01T07:00:00Z', '2026-11-02T08:00:00Z'],
    ['Asia/Kolkata', '2026-03-07T18:30:00Z', '2026-03-08T18:30:00Z'],
    ['America/Sao_Paulo', '2018-11-04T03:00:00Z', '2018-11-05T02:00:00Z'],
    ['America/Sao_Paulo', '2019-02-16T02:00:00Z', '2019-02-17T03:00:00Z'],
    ['Australia/Lord_Howe', '2026-04-04T13:00:00Z', '2026-04-05T13:30:00Z'],
    ['Pacific/Apia', '2011-12-29T10:00:00Z', '2011-12-30T10:00:00Z'],
  ])('accepts the complete local day in %s (%s)', (zone, start, end) => {
    expect(isValidDailyStepDeletion(input(start, end, zone))).toBe(true);
  });

  it('accepts an original ISO offset instant and preserves unrelated record fields', () => {
    const value = input(
      '2026-03-08T08:00:00Z',
      '2026-03-09T07:00:00Z',
      'America/Los_Angeles',
      '2026-03-08T12:34:56.789-07:00',
    );
    value.record.future = { nested: ['opaque'] };
    const before = JSON.stringify(value);
    expect(isValidDailyStepDeletion(value)).toBe(true);
    expect(JSON.stringify(value)).toBe(before);
  });

  it.each([
    ['2026-03-08T12:00:00Z', '2026-03-09T12:00:00Z'],
    ['2026-03-08T00:00:00.001Z', '2026-03-09T00:00:00Z'],
    ['2026-03-08T00:00:00Z', '2026-03-08T23:59:59.999Z'],
    ['2026-03-08T00:00:00Z', '2026-03-10T00:00:00Z'],
    ['2026-03-01T00:00:00Z', '2026-04-01T00:00:00Z'],
    ['2026-01-01T00:00:00Z', '2027-01-01T00:00:00Z'],
    ['2026-03-08T00:00:00Z', '2026-03-08T00:00:00Z'],
  ])('rejects incomplete or wider envelopes %s to %s', (start, end) => {
    expect(isValidDailyStepDeletion(input(start, end))).toBe(false);
  });

  it.each(['2026-03-07T23:59:59.999Z', '2026-03-09T00:00:00Z'])(
    'rejects an original date outside the half-open day: %s',
    (date) => {
      expect(
        isValidDailyStepDeletion(
          input('2026-03-08T00:00:00Z', '2026-03-09T00:00:00Z', 'UTC', date),
        ),
      ).toBe(false);
    },
  );

  it.each([
    '',
    'invalid',
    '2026-02-30T12:00:00Z',
    '2025-02-29T12:00:00Z',
    '2026-03-08',
    '2026-03-08T12:00:00',
    '2026-03-08T24:00:00Z',
    '2026-03-08T12:00:60Z',
    '2026-03-08T12:00:00.000000001Z',
  ])('rejects malformed or normalized dates: %s', (date) => {
    expect(
      isValidDailyStepDeletion(input('2026-03-08T00:00:00Z', '2026-03-09T00:00:00Z', 'UTC', date)),
    ).toBe(false);
  });

  it.each(['Mars/Olympus', '+05:30', ' UTC', '', 'America/Los_Angeles/invalid'])(
    'rejects invalid named zones: %s',
    (zone) => {
      expect(
        isValidDailyStepDeletion(input('2026-03-08T00:00:00Z', '2026-03-09T00:00:00Z', zone)),
      ).toBe(false);
    },
  );

  it('rejects a fixed 24-hour approximation across DST', () => {
    expect(
      isValidDailyStepDeletion(
        input('2026-03-08T08:00:00Z', '2026-03-09T08:00:00Z', 'America/Los_Angeles'),
      ),
    ).toBe(false);
    expect(
      isValidDailyStepDeletion(
        input('2026-11-01T07:00:00Z', '2026-11-02T07:00:00Z', 'America/Los_Angeles'),
      ),
    ).toBe(false);
  });

  it('rejects missing fields, arrays and non-UUID records', () => {
    expect(isValidDailyStepDeletion(null)).toBe(false);
    expect(isValidDailyStepDeletion([])).toBe(false);
    expect(isValidDailyStepDeletion({})).toBe(false);
    const value = input('2026-03-08T00:00:00Z', '2026-03-09T00:00:00Z');
    expect(isValidDailyStepDeletion({ ...value, record: [] })).toBe(false);
    expect(
      isValidDailyStepDeletion({ ...value, record: { ...value.record, id: 'not-a-uuid' } }),
    ).toBe(false);
  });
});
