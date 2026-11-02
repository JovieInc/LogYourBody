import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../..');
const read = (path: string) => readFileSync(resolve(root, path), 'utf8');
const record = JSON.parse(read('packages/shared-lib/decisions/client-qualification-order.json'));

function normalize(value: string): string {
  return value.replace(/\s+/g, ' ');
}

function headingSlug(heading: string): string {
  return heading.toLowerCase().replace(/:/g, '').replace(/ /g, '-');
}

describe('LYB-275 client qualification order', () => {
  it('adopts the unanswered default without accounts, registrations, or connections', () => {
    expect(record).toMatchObject({
      id: 'LYB-275',
      parent: 'LYB-163',
      depends_on: 'LYB-161',
      status: 'accepted',
      recorded_on: '2026-11-01',
      authorizes_feature_work: false,
      authorizes_account_connection: false,
      authorizes_client_registration: false,
      authorizes_real_user_data: false,
      creates_linear_issues: false,
      creates_admission_labels: false,
    });
    expect(record.approval_basis).toContain('ships-if-unanswered');
    expect(record.decision).toContain('Claude Code first');
    expect(record.decision).toContain('synthetic fixture account only');
    expect(record.decision).toContain('then ChatGPT, then Jovie');
    expect(record.decision).toContain('not provided');
    expect(record.providers).toMatchObject({
      synthetic_fixtures: 'LYB-275',
      consented_test_accounts: 'account_owner',
      client_registrations: 'account_owner',
      redirect_uris: 'account_owner',
      account_owner: 'Tim',
      agent_may_supply_real_accounts: false,
    });
    expect(record.consented_test_accounts_provided).toEqual([]);
    expect(record.client_registrations_provided).toEqual([]);
    expect(record.boundaries).toContain('Real-device TestFlight evidence stays with LYB-161');
  });

  it('lists only the two synthetic fixtures and leaves provider steps unexecuted', () => {
    expect(record.accounts_provided).toEqual([
      expect.objectContaining({
        id: 'fixture-a',
        kind: 'synthetic_fixture',
        role: 'subject_a',
        provided_by: 'LYB-275',
        real_user_data: false,
        credentials: 'none',
        client_id: null,
        redirect_uri: null,
      }),
      expect.objectContaining({
        id: 'fixture-b',
        kind: 'synthetic_fixture',
        role: 'subject_b',
        provided_by: 'LYB-275',
        real_user_data: false,
        credentials: 'none',
        client_id: null,
        redirect_uri: null,
      }),
    ]);
    expect(record.provider_steps.map((step: { status: string }) => step.status)).toEqual([
      'not_run',
      'not_provided',
      'not_accepted',
    ]);
    const serialized = JSON.stringify(record);
    expect(serialized).not.toMatch(/@/);
    expect(serialized).not.toMatch(/client_secret|bearer|sk_live|sk-/i);
  });

  it('creates one unexecuted slice per client in qualification order', () => {
    expect(record.slices.map((slice: { key: string }) => slice.key)).toEqual([
      'claude_code',
      'chatgpt',
      'jovie',
    ]);
    expect(record.slices.map((slice: { order: number }) => slice.order)).toEqual([1, 2, 3]);
    expect(record.slices[0]).toEqual(
      expect.objectContaining({
        key: 'claude_code',
        implementation: 'authorized_synthetic_fixture_only',
        starts_when: 'recorded',
      }),
    );
    expect(record.slices[1]).toEqual(
      expect.objectContaining({
        key: 'chatgpt',
        implementation: 'authorized_after_claude_code_synthetic_passes',
        starts_when: 'claude_code_synthetic_passes',
      }),
    );
    expect(record.slices[2]).toEqual(
      expect.objectContaining({
        key: 'jovie',
        implementation: 'authorized_after_chatgpt_synthetic_passes',
        starts_when: 'chatgpt_synthetic_passes',
      }),
    );
    for (const slice of record.slices) {
      expect(slice.implemented, slice.key).toBe(false);
      expect(slice.feature_work, slice.key).toBe(false);
      expect(slice.account_connection, slice.key).toBe(false);
      expect(slice.qualifies_other_clients, slice.key).toBe(false);
      expect(slice.linear_issue, slice.key).toBeNull();
      expect(slice.registration, slice.key).toBe('not_provided');
      expect(slice.real_consented_account, slice.key).toBe('not_provided');
      expect(slice.real_account_provider, slice.key).toBe('account_owner');
      expect(slice.client_id, slice.key).toBeNull();
      expect(slice.redirect_uri, slice.key).toBeNull();
      expect(slice.accounts, slice.key).toEqual(['fixture-a', 'fixture-b']);
    }
  });

  it('links each slice to a specification heading', () => {
    const spec = read(record.specification);
    const headings = [...spec.matchAll(/^### (.+)$/gm)].map((match) => headingSlug(match[1]));
    for (const slice of record.slices) {
      const [path, anchor] = slice.specification.split('#');
      expect(path, slice.key).toBe(record.specification);
      expect(headings, slice.key).toContain(anchor);
      expect(spec, slice.key).toContain(`Key: \`${slice.key}\`.`);
      expect(spec, slice.key).toContain(`Implementation: \`${slice.implementation}\`.`);
    }
    expect(spec).toContain('fixture-a');
    expect(spec).toContain('fixture-b');
    expect(spec).toContain('not Linear issue IDs');
  });

  it('records the same order on the roadmap, runbook, inventory, and journeys', () => {
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
    for (const phrase of record.required_boundary_phrases) {
      expect(boundary, phrase).toContain(normalize(phrase));
    }
    const documents = [record.runbook, record.inventory, record.journeys].map((path) =>
      normalize(read(path)),
    );
    for (const phrase of record.required_cross_document_phrases) {
      const expected = normalize(phrase);
      expect(current, phrase).toContain(expected);
      for (const document of documents) {
        expect(document, phrase).toContain(expected);
      }
    }
  });
});
