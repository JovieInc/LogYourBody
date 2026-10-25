/** @jest-environment node */
import { NextRequest } from 'next/server';
import { createTrainingRevisionHandlers } from '../revision-route-handlers';
import { revisionHarness } from '@/lib/training/revisions.testing';
import { delegatedProgrammingEnabled } from '@/lib/flags/delegated-programming';
import { findTool, listTools } from '@/lib/mcp/tools';

function harness() {
  const h = revisionHarness();
  h.context.evidenceFingerprint = 'current-training';
  h.context.canonicalTrainingInputs = {
    goal: 'Build muscle',
    experience: 'new',
    sessionsPerWeek: 2,
    minutesPerSession: 60,
    equipment: 'full_gym',
    limitations: [],
    excludedVariantIds: [],
    preferredVariantIds: [],
  };
  const deps = {
    authenticate: async () => ({ sub: 'owner' }),
    records: h.records,
    revisions: h.port,
    reserveRequest: async () =>
      ({ allowed: true, remainingInWindow: 9, remainingToday: 99 }) as const,
    now: () => new Date('2026-10-25'),
    enabled: () => true,
    delegatedEnabled: () => true,
  };
  return { ...h, deps, handlers: createTrainingRevisionHandlers(deps) };
}
const body = {
  requestId: '11111111-1111-4111-8111-111111111111',
  expectedGeneration: 0,
  reason: 'Recommend my plan',
  intent: { kind: 'recommend', inputs: {}, adultConfirmed: true, safetyConfirmed: true },
};
const request = (method: string, data?: unknown, query = '') =>
  new NextRequest(`http://localhost/api/auth/mobile/training/v1/program-proposals${query}`, {
    method,
    ...(data
      ? { body: JSON.stringify(data), headers: { 'content-type': 'application/json' } }
      : {}),
  });

describe('delegated programming client boundary', () => {
  it('requires both default-off server gates and keeps MCP tools hidden before rollout', () => {
    expect(delegatedProgrammingEnabled({})).toBe(false);
    expect(delegatedProgrammingEnabled({ LYB_DELEGATED_PROGRAMMING_ENABLED: 'true' })).toBe(false);
    expect(listTools().some((t) => t.name === 'revise_training_program')).toBe(false);
    expect(listTools(true).some((t) => t.name === 'revise_training_program')).toBe(true);
  });
  it('returns one persisted coach recommendation and exposes it for native/chat review without enrollment', async () => {
    const h = harness();
    const response = await h.handlers.POST(request('POST', body));
    expect(response.status).toBe(201);
    const saved = await response.json();
    const read = await h.handlers.GET(request('GET'));
    expect(await read.json()).toMatchObject({
      delegatedProgramming: true,
      pendingProposal: saved.stored,
    });
    expect(saved.stored.proposal.actor).toEqual({ kind: 'coach', subject: 'lyb-coach' });
    expect(h.context.headRevision).toBeNull();
    expect(h.port.decide).not.toHaveBeenCalled();
  });
  it('returns one focused question, rejects caller-supplied authority, and denies ungranted trainers', async () => {
    const h = harness();
    h.context.canonicalTrainingInputs = {};
    const response = await h.handlers.POST(request('POST', body));
    expect(await response.json()).toMatchObject({ kind: 'question', field: 'goal' });
    expect(h.port.createProposal).not.toHaveBeenCalled();
    expect(
      (
        await h.handlers.POST(
          request('POST', { ...body, actor: { kind: 'trainer', subject: 'forged' } }),
        )
      ).status,
    ).toBe(400);
    expect((await h.handlers.GET(request('GET', undefined, '?owner=other'))).status).toBe(403);
  });
  it('MCP proposes through the same ledger and cannot apply or fabricate from free text', async () => {
    const h = harness();
    const tool = findTool('revise_training_program')!;
    const deps = { ...h.deps, createId: () => body.requestId };
    const result = await tool.run('owner', { action: 'propose', proposal: body } as never, deps);
    expect(result.structuredContent).toMatchObject({
      kind: 'stored',
      stored: { status: 'proposed' },
    });
    expect(h.port.decide).not.toHaveBeenCalled();
    const disabled = await tool.run('owner', { action: 'propose', proposal: body } as never, {
      ...deps,
      delegatedEnabled: () => false,
    });
    expect(disabled.isError).toBe(true);
  });
});
