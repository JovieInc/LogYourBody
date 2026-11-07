import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../..');
const read = (path: string) => readFileSync(resolve(root, path), 'utf8');
const normalize = (value: string) => value.replace(/\s+/g, ' ');
const record = JSON.parse(read('packages/shared-lib/decisions/bodyspec-event-support.json'));

describe('LYB-246 BodySpec capability finding', () => {
  it('adopts polling-only when no provider account is available', () => {
    expect(record).toMatchObject({
      id: 'LYB-246',
      parent: 'LYB-171',
      status: 'accepted',
      recorded_on: '2026-11-01',
      decision: 'polling_only',
      adapter_slice: 'docs/architecture/metric-source-adapters.md',
      live_validation: false,
      authorizes_partner_webhook_client: false,
      invents_mcp_events: false,
      testflight_evidence_owner: 'LYB-171',
    });
    expect(record.approval_basis).toContain('ships-if-unanswered');
    expect(record.question).toContain('BodySpec test account');
    expect(record.openapi).toEqual({
      url: 'https://app.bodyspec.com/openapi.json',
      docs_url: 'https://app.bodyspec.com/docs',
      retrieved_on: '2026-11-01',
      openapi: '3.1.0',
      info_version: '0.20.0',
      sha256: 'fb531c62157e0ac2061aa43c65d67ed5a4a528608431cafcc4591f038b40662a',
    });
  });

  it('records push, incremental pull, and unpublished rate limits', () => {
    expect(record.push).toEqual({
      mcp_events: false,
      user_oauth_events: false,
      partner_webhooks_documented: true,
      partner_event_types: [
        'results_ready',
        'reservation_created',
        'reservation_canceled',
        'reservation_no_show',
      ],
      results_ready_delivery: 'at_least_once',
      dedupe_key: 'data.result_id',
      registration_can_return_503: true,
      adapter_push_events: false,
    });
    expect(record.incremental_pull).toEqual({
      supported: true,
      endpoint: '/api/v1/users/me/results/',
      page_param: 'page',
      page_size_param: 'page_size',
      page_size_default: 20,
      page_size_max: 100,
      has_more: true,
      server_cursor: false,
      results_time_filter: false,
      client_filters_start_time: true,
      adapter_incremental_pull: true,
    });
    expect(record.rate_limits).toEqual({
      published_quota: null,
      documents_429: false,
      documents_retry_after: false,
      live_headers_observed: false,
    });
    expect(record.polling_policy).toEqual({
      mode: 'scheduled_incremental_pull',
      on_app_open: true,
      daily_check: true,
      installs_app_open_caller: false,
      installs_background_timer: false,
      installs_event_endpoint: false,
      adapter_scheduled_poll: true,
    });
    expect(record.revisit_when).toContain('partner account');
  });

  it('attaches the same finding to the adapter slice and leaves push disabled', () => {
    const adapter = normalize(read(record.adapter_slice));
    for (const phrase of record.required_adapter_phrases) {
      expect(adapter, phrase).toContain(normalize(phrase));
    }
    expect(adapter).toContain(normalize(record.capability_row));
    expect(adapter).toContain('TestFlight evidence remains with LYB-171.');
    expect(adapter).not.toContain('BodySpec event support is unverified');

    const importer = read('apps/ios/LogYourBody/Services/BodySpecDexaImporter.swift');
    const capabilities = importer
      .split('\n')
      .find((line) => line.includes('let capabilities = MetricSourceCapabilities'));
    expect(capabilities).toBe(
      '    nonisolated let capabilities = MetricSourceCapabilities(incrementalPull: true, scheduledPoll: true)',
    );
    expect(importer).toContain('LYB-246');
    expect(importer).not.toContain('pushEvents: true');
  });
});
