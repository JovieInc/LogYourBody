import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../..');
const read = (path: string) => readFileSync(resolve(root, path), 'utf8');
const record = JSON.parse(read('packages/shared-lib/decisions/agent-parity-slices.json'));

function normalize(value: string): string {
  return value.replace(/\s+/g, ' ');
}

function headingSlug(heading: string): string {
  return heading.toLowerCase().replace(/:/g, '').replace(/ /g, '-');
}

describe('LYB-274 agent parity slice decision', () => {
  it('adopts the unanswered default and authorizes one post-shipment check', () => {
    expect(record).toMatchObject({
      id: 'LYB-274',
      parent: 'LYB-161',
      depends_on: 'LYB-162',
      status: 'accepted',
      recorded_on: '2026-11-01',
      authorizes_feature_work: false,
      creates_linear_issues: false,
    });
    expect(record.approval_basis).toContain('ships-if-unanswered');
    expect(record.decision).toContain('next slice only');
    expect(record.decision).toContain('no feature work');
    expect(record.decision).toContain('after the current TestFlight release ships');
    expect(record.boundaries).toContain('Real-device TestFlight evidence stays with LYB-161');
  });

  it('creates exactly the named slices and authorizes only the inventory check', () => {
    expect(record.slices.map((slice: { key: string }) => slice.key)).toEqual([
      'inventory_check',
      'goals_preferences',
      'trends',
      'photos_imports',
      'glp1',
      'export_deletion',
      'integration_status',
    ]);
    const authorized = record.slices.filter(
      (slice: { implementation: string }) => slice.implementation !== 'not_authorized',
    );
    expect(authorized).toEqual([
      expect.objectContaining({
        key: 'inventory_check',
        title: 'Inventory check',
        implementation: 'authorized_after_current_testflight_ships',
        kind: 'ci_check',
        feature_work: false,
        implemented: false,
        covers: 'every_canonical_inventory_row',
        linear_issue: null,
      }),
    ]);
    for (const slice of record.slices) {
      expect(slice.implemented, slice.key).toBe(false);
      expect(slice.feature_work, slice.key).toBe(false);
      expect(slice.linear_issue, slice.key).toBeNull();
      if (slice.key !== 'inventory_check') {
        expect(slice.implementation, slice.key).toBe('not_authorized');
        expect(slice.kind, slice.key).toBe('feature_gap');
      }
    }
  });

  it('links each slice to a specification heading and an inventory anchor', () => {
    const spec = read(record.specification);
    const inventoryDoc = read(record.inventory);
    const inventoryStart = inventoryDoc.indexOf('## Canonical iOS capability inventory');
    const inventoryEnd = inventoryDoc.indexOf('### Execution-boundary handoff contract');
    expect(inventoryStart).toBeGreaterThanOrEqual(0);
    expect(inventoryEnd).toBeGreaterThan(inventoryStart);
    const inventory = inventoryDoc.slice(inventoryStart, inventoryEnd);
    const headings = [...spec.matchAll(/^### (.+)$/gm)].map((match) => headingSlug(match[1]));
    for (const slice of record.slices) {
      const [path, anchor] = slice.specification.split('#');
      expect(path, slice.key).toBe(record.specification);
      expect(headings, slice.key).toContain(anchor);
      expect(spec, slice.key).toContain(`Key: \`${slice.key}\`.`);
      expect(spec, slice.key).toContain(`Implementation: \`${slice.implementation}\`.`);
      expect(slice.inventory_anchors.length, slice.key).toBeGreaterThan(0);
      for (const phrase of slice.inventory_anchors) {
        expect(inventory, phrase).toContain(phrase);
      }
    }
  });

  it('records the same authorization on the roadmap, inventory and journeys', () => {
    const roadmap = read(record.roadmap);
    const start = roadmap.indexOf(record.current_section.start);
    const end = roadmap.indexOf(record.current_section.end);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);
    const current = normalize(roadmap.slice(start, end));
    for (const phrase of record.required_current_phrases) {
      expect(current, phrase).toContain(normalize(phrase));
    }
    const boundary = normalize(
      roadmap.slice(roadmap.indexOf(record.planning_boundary_start), start),
    );
    for (const phrase of record.preserved_boundary_phrases) {
      expect(boundary, phrase).toContain(normalize(phrase));
    }
    const journeys = normalize(read(record.journeys));
    const inventoryDoc = normalize(read(record.inventory));
    for (const phrase of record.required_cross_document_phrases) {
      const expected = normalize(phrase);
      expect(current, phrase).toContain(expected);
      expect(journeys, phrase).toContain(expected);
      expect(inventoryDoc, phrase).toContain(expected);
    }
  });
});
