import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../..');
const read = (path: string) => readFileSync(resolve(root, path), 'utf8');
// Package-local decision inputs invalidate the existing shared-lib CI cache.
// These checks preserve the decision contract; they do not execute an engine.
const record = JSON.parse(read('packages/shared-lib/decisions/deload-postponement.json'));

describe('LYB-267 deload postponement decision', () => {
  it('records the authorized default without implying clinical approval', () => {
    expect(record).toMatchObject({
      id: 'LYB-267',
      parent: 'LYB-173',
      status: 'accepted',
      recorded_on: '2026-11-01',
      bounds: { maximum_postponements: 1, maximum_delay_calendar_days: 7 },
    });
    expect(record.approval_basis).toContain('ships-if-unanswered');
    expect(record.evidence.uncertainty).toContain('issue-authorized product bounds');
    expect(record.evidence.uncertainty).toContain('does not establish');
  });

  it('retains stronger restrictions and makes a check-in insufficient for another allowance', () => {
    expect(record.bounds.non_postponable).toEqual([
      'pain_or_symptom_pause',
      'reactive_recovery_reduction',
      'planned_deload_boundary',
      'coaching_ineligible',
    ]);
    expect(record.bounds.second_request).toContain('not permission for a second postponement');
    expect(record.bounds.at_deadline).toContain('Stop recommending continuation');
    expect(record.bounds.deadline_anchor).toContain('original proposed deload start date');
    expect(record.bounds.volume_cap).toContain('Existing lower recovery limits still win');
  });

  it('keeps committed postponement and hold receipts distinct from engine deferral wording', () => {
    const [path, moment] = record.receipts.distinct_from.split('#');
    const wording = JSON.parse(read(path));
    expect(wording.id).toBe('LYB-302');
    expect(wording.moments[moment]).toBeTruthy();
    expect(record.receipts.postponed).toBe(
      'Deload postponed to {date}; volume capped at current level.',
    );
    expect(record.receipts.check_in_required).toContain('check in on fatigue');
    expect(record.receipts.check_in_required).toContain('Your deload date stays {date}');
    expect(record.receipts.limit_reached).toContain('already been postponed once');
    for (const key of ['postponed', 'check_in_required', 'limit_reached']) {
      expect(record.receipts[key]).not.toBe(wording.moments[moment]);
      expect(record.receipts[key]).not.toMatch(
        /\b(?:safe|cleared|diagnos\w*|overtrain\w*|prevent\w*|guarantee\w*|improv\w*)\b/i,
      );
    }
    expect(record.receipts.success_condition).toContain('durably saved together');
  });

  it('creates one linked engine slice and keeps policy and receipt examples consistent', () => {
    expect(record.engine_slice).toMatchObject({
      key: 'deload_postponement',
      status: 'ready_for_implementation',
      depends_on: ['LYB-267'],
      runtime_implemented: false,
    });
    const [path, anchor] = record.engine_slice.specification.split('#');
    const specification = read(path);
    const headings = [...specification.matchAll(/^### (.+)$/gm)].map((match) =>
      match[1].toLowerCase().replace(/:/g, '').replace(/ /g, '-'),
    );
    expect(headings).toContain(anchor);
    for (const key of ['postponed', 'check_in_required', 'limit_reached']) {
      expect(specification).toContain(record.receipts[key].replace('{date}', 'Mar 12'));
    }
    for (const path of record.standards) expect(read(path).trim()).toBeTruthy();
  });
});
