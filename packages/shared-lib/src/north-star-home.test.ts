import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../..');
const read = (path: string) => readFileSync(resolve(root, path), 'utf8');
const record = JSON.parse(read('packages/shared-lib/decisions/north-star-home.json'));

function normalize(value: string): string {
  return value.replace(/\s+/g, ' ');
}

function currentContract(roadmap: string): string {
  const start = roadmap.indexOf(record.current_section.start);
  const end = roadmap.indexOf(record.current_section.end);
  expect(start).toBeGreaterThanOrEqual(0);
  expect(end).toBeGreaterThan(start);
  return normalize(roadmap.slice(start, end));
}

describe('LYB-173 October 28 home contract', () => {
  const roadmap = read(record.roadmap);
  const current = currentContract(roadmap);

  it('keeps the body-through-time Home and one action as current policy', () => {
    expect(record).toMatchObject({ id: 'LYB-173', status: 'accepted', recorded_on: '2026-11-01' });
    expect(record.decision).toContain('body through time');
    expect(record.decision).toContain('does not implement');
    for (const phrase of record.required_current_phrases) {
      expect(current, phrase).toContain(normalize(phrase));
    }
    for (const phrase of record.forbidden_current_phrases) {
      expect(current, phrase).not.toContain(normalize(phrase));
    }
  });

  it('preserves the September timeline-first wording as history', () => {
    const history = roadmap.slice(roadmap.indexOf(record.current_section.end));
    expect(history).toContain(record.preserved_history_phrase);
    expect(current).not.toContain(record.preserved_history_phrase);
  });

  it('points the older supersession banners at the same body canvas', () => {
    for (const path of record.aligned_documents) {
      expect(normalize(read(path)), path).toContain('body through time');
    }
  });
});
