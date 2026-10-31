/** @jest-environment node */

import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';
import { NextRequest } from 'next/server';
import { createTrainingRevisionHandlers } from '@/app/api/auth/mobile/training/v1/revision-route-handlers';
import { handleMcpRequest, type McpHandlerDependencies } from '@/lib/mcp/handler';
import { LYB_MCP_SCOPES } from '@/lib/mcp/contract';
import { TRAINING_PRICING_BOUNDARY_POLICY } from './pricing-boundary-policy';
import { decisionBody, proposalBody, revisionHarness } from './revisions.testing';

const canonical = 'apps/web/src/lib/training/pricing-boundary-policy.ts';
const capabilities = ['readPrice', 'checkEntitlement', 'checkout', 'failedPayment', 'cancel'];
type Source = [string, string];

function assertSinglePolicy(sources: Source[]) {
  const definitions: string[] = [];
  for (const [file, source] of sources) {
    const tree = ts.createSourceFile(
      file,
      source.trimStart().startsWith('{') ? `(${source})` : source,
      ts.ScriptTarget.Latest,
      true,
    );
    function visit(node: ts.Node) {
      if (
        ts.isVariableDeclaration(node) &&
        node.name.getText(tree) === 'TRAINING_PRICING_BOUNDARY_POLICY'
      ) {
        definitions.push(file);
        return;
      }
      if (ts.isObjectLiteralExpression(node)) {
        const keys = node.properties.flatMap((property) =>
          ts.isPropertyAssignment(property) &&
          (property.initializer.kind === ts.SyntaxKind.FalseKeyword ||
            property.initializer.kind === ts.SyntaxKind.TrueKeyword)
            ? [property.name.getText(tree).replace(/^['"]|['"]$/g, '')]
            : [],
        );
        if (capabilities.every((key) => keys.includes(key))) {
          definitions.push(file);
          return;
        }
      }
      ts.forEachChild(node, visit);
    }
    visit(tree);
  }
  expect(definitions.sort()).toEqual([canonical]);
}

describe('training pricing boundary decision (LYB-282)', () => {
  it('reads exactly one production policy across apps, packages and agent sources', () => {
    const root = resolve(process.cwd(), '../..');
    function collect(directory: string): Source[] {
      return readdirSync(resolve(root, directory), { withFileTypes: true }).flatMap((entry) => {
        const file = `${directory}/${entry.name}`;
        if (entry.isDirectory())
          return /^(?:node_modules|dist|build|coverage|Vendor|Pods|DerivedData|test_results|fixtures|__tests__|\..*)$/.test(
            entry.name,
          )
            ? []
            : collect(file);
        return entry.isFile() &&
          /\.(?:[cm]?[jt]sx?|json)$/.test(file) &&
          !/\.(?:test|spec|testing)\./.test(file)
          ? [[file, readFileSync(resolve(root, file), 'utf8')] as Source]
          : [];
      });
    }
    assertSinglePolicy(['apps', 'packages', 'agent'].flatMap(collect));
    expect(TRAINING_PRICING_BOUNDARY_POLICY).toEqual({
      readPrice: false,
      checkEntitlement: false,
      checkout: false,
      failedPayment: false,
      cancel: false,
    });
    expect(Object.isFrozen(TRAINING_PRICING_BOUNDARY_POLICY)).toBe(true);
  }, 30_000);

  it('fails for a missing or duplicated policy, including renamed and JSON copies', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'src/lib/training/pricing-boundary-policy.ts'),
      'utf8',
    );
    const original: Source = [canonical, source];
    expect(() => assertSinglePolicy([])).toThrow();
    assertSinglePolicy([original]);
    for (const copy of [
      source,
      source.replaceAll('TRAINING_PRICING_BOUNDARY_POLICY', 'otherDecision'),
      JSON.stringify(TRAINING_PRICING_BOUNDARY_POLICY),
    ])
      expect(() => assertSinglePolicy([original, ['agent/second-policy.ts', copy]])).toThrow();
    expect(() => assertSinglePolicy([[canonical, `${source}\n${source}`]])).toThrow();
    assertSinglePolicy([
      original,
      ['agent/consumer.ts', "export { TRAINING_PRICING_BOUNDARY_POLICY } from './policy';"],
      // Billing implementations belong to LYB-48 / LYB-138, outside this policy.
      [
        'apps/web/src/lib/billing/adapter.ts',
        `export const billing = {
        readPrice() {}, checkEntitlement() {}, checkout() {}, failedPayment() {}, cancel() {}
      }; export const pricingPolicy = { currency: 'USD' };`,
      ],
    ]);
  });
});

const now = () => new Date('2026-10-31T12:00:00Z');
const reserveRequest = async () => ({
  allowed: true as const,
  remainingInWindow: 9,
  remainingToday: 99,
});
const request = (method = 'GET', body?: unknown, query = '') =>
  new NextRequest(`http://localhost/api/auth/mobile/training/v1/program-proposals${query}`, {
    method,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });

describe('revision and training MCP handler billing isolation', () => {
  // Keep explicit spies even when a handler catches a thrown billing error.
  const billing = Object.fromEntries(
    Object.entries(TRAINING_PRICING_BOUNDARY_POLICY).map(([capability, allowed]) => {
      if (allowed) throw new Error(`Unexpected billing permission: ${capability}`);
      return [
        capability,
        jest
          .fn(() => {
            throw new Error(`Billing call: ${capability}`);
          })
          .mockName(`billing.${capability}`),
      ];
    }),
  );
  const billingTraps = { ...billing, billing };
  beforeEach(() => jest.clearAllMocks());
  afterEach(() => {
    for (const call of Object.values(billing)) expect(call).not.toHaveBeenCalled();
  });

  it.each([false, true])(
    'reads, proposes, applies and rejects cycle revisions without billing (delegated=%s)',
    async (delegatedEnabled) => {
      const h = revisionHarness();
      const handlers = createTrainingRevisionHandlers({
        ...billingTraps,
        revisions: h.port,
        records: h.records,
        authenticate: async () => ({ sub: 'owner' }) as never,
        reserveRequest,
        now,
        enabled: () => true,
        delegatedEnabled: () => delegatedEnabled,
      });
      expect((await handlers.GET(request())).status).toBe(200);
      const created = await handlers.POST(request('POST', proposalBody));
      expect(created.status).toBe(201);
      const { stored } = await created.json();
      const applied = await handlers.PATCH(request('PATCH', decisionBody(stored.proposal.id)));
      expect(applied.status).toBe(200);
      expect(await applied.json()).toMatchObject({ receipt: { status: 'applied' } });
      h.context.trainingFingerprint = 'fresh-cycle';
      const revised = await handlers.POST(
        request('POST', {
          ...proposalBody,
          requestId: '88888888-8888-4888-8888-888888888888',
          intent: { kind: 'revise_cycle', weekCount: 4 },
        }),
      );
      expect(revised.status).toBe(201);
      const revision = (await revised.json()).stored;
      expect(
        (await handlers.GET(request('GET', undefined, `?id=${revision.proposal.id}`))).status,
      ).toBe(200);
      const rejected = await handlers.PATCH(
        request('PATCH', decisionBody(revision.proposal.id, 'reject')),
      );
      expect(rejected.status).toBe(200);
      expect(await rejected.json()).toMatchObject({ receipt: { status: 'rejected' } });
    },
  );

  it.each([false, true])(
    'runs training MCP tools without billing (delegated=%s)',
    async (delegatedEnabled) => {
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
      const revisions = createTrainingRevisionHandlers({
        ...billingTraps,
        revisions: h.port,
        records: h.records,
        authenticate: async () => ({ sub: 'owner' }) as never,
        reserveRequest,
        now,
        enabled: () => true,
      });
      const deps = {
        ...billingTraps,
        records: h.records,
        revisions: h.port,
        delegatedEnabled: () => delegatedEnabled,
        now,
        createId: () => '33333333-3333-4333-8333-333333333333',
        resourceUrl: 'http://localhost/api/mcp',
        reserveRequest,
      } satisfies McpHandlerDependencies;
      async function rpc(method: string, params?: unknown) {
        const response = await handleMcpRequest({
          body: { jsonrpc: '2.0', id: 1, method, params },
          principal: {
            subject: 'owner',
            clientId: 'synthetic',
            scopes: new Set([LYB_MCP_SCOPES.trainingRead, LYB_MCP_SCOPES.trainingWrite]),
          },
          deps,
        });
        expect(response.status).toBe(200);
        expect(response.body).not.toHaveProperty('error');
        const result = (response.body as { result: Record<string, any> }).result;
        expect(result).not.toHaveProperty('isError', true);
        return result;
      }
      const called = new Set<string>();
      const call = (name: string, args = {}) => {
        called.add(name);
        return rpc('tools/call', { name, arguments: args });
      };
      await rpc('initialize');
      const listed = await rpc('tools/list');
      expect(listed.tools).toHaveLength(delegatedEnabled ? 8 : 7);
      if (delegatedEnabled) {
        await call('revise_training_program', { action: 'read' });
        expect(
          (
            await call('revise_training_program', {
              action: 'propose',
              proposal: {
                ...proposalBody,
                requestId: '44444444-4444-4444-8444-444444444444',
                intent: {
                  kind: 'recommend',
                  inputs: {},
                  adultConfirmed: true,
                  safetyConfirmed: true,
                },
              },
            })
          ).structuredContent,
        ).toMatchObject({ kind: 'stored', stored: { status: 'proposed' } });
      }
      expect((await call('get_todays_workout')).structuredContent).toEqual({
        status: 'not_enrolled',
      });
      const created = await revisions.POST(request('POST', proposalBody));
      expect(created.status).toBe(201);
      const { stored } = await created.json();
      expect(
        (await revisions.PATCH(request('PATCH', decisionBody(stored.proposal.id)))).status,
      ).toBe(200);
      expect((await call('get_todays_workout')).structuredContent).toMatchObject({
        status: 'workout',
      });
      expect(
        (
          await call('log_sets', {
            exercise: 'goblet_squat',
            sets: [{ reps: 8, rir: 3, load: 20 }],
          })
        ).structuredContent,
      ).toMatchObject({ logged: [{ reps: 8, rir: 3, loadKg: 20 }] });
      await call('correct_set', {
        exercise: 'goblet_squat',
        setNumber: 1,
        reps: 9,
        rir: 2,
        load: 20,
      });
      await call('swap_exercise', { exercise: 'goblet_squat', variant: 'dumbbell_split_squat' });
      await call('control_workout', { action: 'pause' });
      await call('control_workout', { action: 'resume' });
      await call('log_session_feedback', {
        soreness: 2,
        pump: 4,
        performance: 'stable',
        jointPain: 0,
      });
      expect((await call('get_training_progress')).structuredContent).toMatchObject({
        enrolled: true,
        setsLast7Days: 1,
      });
      expect([...called].sort()).toEqual(
        listed.tools.map((tool: { name: string }) => tool.name).sort(),
      );
    },
  );
});
