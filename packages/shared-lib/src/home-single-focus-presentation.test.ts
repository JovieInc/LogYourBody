import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../..');
const read = (path: string) => readFileSync(resolve(root, path), 'utf8');
// Package-local decisions are Turbo inputs. This cross-record check runs in
// existing shared-lib CI; it does not claim native render/snapshot coverage.
const record = JSON.parse(
  read('packages/shared-lib/decisions/home-single-focus-presentation.json'),
);
const wording = JSON.parse(read(record.home_card.wording_from));
const eligibility = JSON.parse(read(record.earned_win.eligibility_from));

describe('LYB-266 Home presentation decision', () => {
  it('records default adoption, restrained presentation and an off-by-default UI rollout', () => {
    expect(record).toMatchObject({ id: 'LYB-266', parent: 'LYB-173', status: 'accepted' });
    expect(record.approval_basis).toContain('ships-if-unanswered');
    expect(record.home_card.maximum_foreground_cards).toBe(1);
    expect(record.home_card.maximum_primary_buttons).toBe(1);
    expect(record.earned_win.confetti).toBe(false);
    expect(record.rollout.default_enabled).toBe(false);
  });

  it('covers every accepted card moment and extra state without replacing LYB-302 wording', () => {
    expect(wording).toMatchObject({ id: 'LYB-302', status: 'accepted' });
    expect(Object.keys(record.home_card.actions).sort()).toEqual(
      [
        ...Object.keys(wording.moments),
        ...Object.keys(record.home_card.additional_copy),
        'earned_win',
      ].sort(),
    );
    expect(record.home_card.actions.calm_nothing_to_do).toBeNull();
    expect(record.home_card.actions.new_weight_import_receipt).toBeNull();
    expect(record.home_card.actions.unavailable).toBeNull();
    expect(record.home_card.additional_copy.unavailable).not.toBe(
      wording.moments.calm_nothing_to_do,
    );
  });

  it('maps every real ranker case and preserves the existing composer placeholder', () => {
    const source = read('apps/ios/LogYourBody/Services/QuickPillRanker.swift');
    const cases = [...source.split('enum QuickPillRanker')[0].matchAll(/case (\w+)/g)].map(
      (match) => match[1],
    );
    expect(cases.length).toBeGreaterThan(0);
    expect(Object.keys(record.composer_pills.labels).sort()).toEqual(cases.sort());
    const placeholder = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2AskPolicy.swift').match(
      /static let composerPlaceholder = "([^"]+)"/,
    );
    expect(record.composer_pills.placeholder).toBe(placeholder?.[1]);
  });

  it('covers exactly the accepted win kinds and makes the forecast a separate conditional clause', () => {
    expect(eligibility).toMatchObject({ id: 'LYB-305', status: 'accepted' });
    expect(record.earned_win.allowed_win_kinds).toEqual(eligibility.allowed_win_kinds);
    expect(Object.keys(record.earned_win.templates).sort()).toEqual(
      [...eligibility.allowed_win_kinds].sort(),
    );
    expect(record.earned_win.templates.goal_relative_gain).toContain('{comparison_date}');
    expect(record.earned_win.templates.goal_relative_gain).not.toContain('{target_date}');
    expect(record.earned_win.forecast_suffix).toContain('{target_date}');
    expect(record.earned_win.forecast_condition).toContain(
      'EarnedWinDetector alone supplies no forecast',
    );
  });

  it('creates exactly one linked implementation slice per surface with snapshot handoffs', () => {
    expect(record.ui_slices.map((slice: { key: string }) => slice.key)).toEqual([
      'home_card',
      'composer_pills',
      'win_and_empty',
    ]);
    for (const slice of record.ui_slices) {
      const [path, anchor] = slice.specification.split('#');
      const headings = [...read(path).matchAll(/^### (.+)$/gm)].map((match) =>
        match[1].toLowerCase().replace(/:/g, '').replace(/ /g, '-'),
      );
      expect(headings).toContain(anchor);
      expect(slice.depends_on.length).toBeGreaterThan(0);
      expect(slice.snapshot_cases).toContain('gate_off');
      expect(slice.snapshot_cases.length).toBeGreaterThan(1);
    }
  });

  it('keeps the static visual reference consistent with approved copy', () => {
    const svg = read(record.visual_reference);
    const copy: Record<string, string> = {
      weight_ask: record.home_card.additional_copy.weight_ask,
      weight_action: record.home_card.actions.weight_ask,
      dismiss: record.home_card.dismiss_label,
      placeholder: record.composer_pills.placeholder,
      gain_example: record.earned_win.templates.goal_relative_gain
        .replace('{direction}', 'Down')
        .replace('{change}', '1.2')
        .replace('{unit}', 'kg')
        .replace('{comparison_date}', 'Sep 14'),
      win_action: record.home_card.actions.earned_win,
      calm: wording.moments.calm_nothing_to_do,
      unavailable: record.home_card.additional_copy.unavailable,
      ...Object.fromEntries(
        Object.entries(record.composer_pills.labels).map(([key, label]) => [`pill_${key}`, label]),
      ),
    };
    const illustratedCopy = Object.fromEntries(
      [...svg.matchAll(/<text\b[^>]*data-copy="([^"]+)"[^>]*>([\s\S]*?)<\/text>/g)].map((match) => [
        match[1],
        match[2].replace(/<[^>]+>/g, '').trim(),
      ]),
    );
    expect(illustratedCopy).toEqual(copy);
    expect(svg).toContain('not a native screenshot');
    expect(read(record.specification)).toContain('home-single-focus.svg');
  });
});
