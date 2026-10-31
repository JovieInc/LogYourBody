/** @jest-environment node */

import { z } from 'zod';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';
import { TRAINING_MCP_V1_ALLOWLIST } from '@/lib/mcp/training-field-allowlist';
import { TRAINING_OUTBOUND_POLICY } from './outbound-policy';
import { delegatedProposalSchema, delegatedReceiptSchema } from './delegation-contract';
import { createDelegatedProposal } from './delegated-revisions';
import {
  initialProposalSchema,
  revisionReceiptSchema,
  storedProposalSchema,
} from './revision-contract';
import { createInitialTrainingProposal, decideInitialTrainingProposal } from './revisions';
import { decisionBody, proposalBody, revisionHarness } from './revisions.testing';

type Fixture = { name: string; schema: z.ZodType; record: unknown };
const canonical = 'apps/web/src/lib/training/outbound-policy.ts';
const policyKeys = ['response', 'coachMessage', 'notification', 'send'];

function definitions(sources: Array<[string, string]>): string[] {
  let found: string[] = [];
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
        /outbound.*policy|policy.*outbound/i.test(node.name.getText(tree))
      ) {
        found = [...found, file];
        return;
      }
      if (ts.isObjectLiteralExpression(node)) {
        const keys = node.properties.map((property) =>
          property.name?.getText(tree).replace(/^['"]|['"]$/g, ''),
        );
        if (policyKeys.every((key) => keys.includes(key))) {
          found = [...found, file];
          return;
        }
      }
      ts.forEachChild(node, visit);
    }
    visit(tree);
  }
  return found.sort();
}

function assertSinglePolicy(sources: Array<[string, string]>) {
  expect(definitions(sources)).toEqual([canonical]);
}

const forbiddenFields = [
  'message',
  'messages',
  'coachMessage',
  'coach_message',
  'prose',
  'text',
  'content',
  'notification',
  'notifications',
  'send',
  'sendMessage',
  'send_message',
  'push',
  'pushNotification',
  'chatPost',
  'chat_post',
];

/** Exercise every raw object, including objects in arrays and open diff records. */
function withField(value: unknown, key: string): unknown[] {
  if (Array.isArray(value))
    return value.flatMap((child, index) =>
      withField(child, key).map((changed) => value.map((v, i) => (i === index ? changed : v))),
    );
  if (!value || typeof value !== 'object') return [];
  const record = value as Record<string, unknown>;
  return [
    { ...record, [key]: 'excluded coach message or delivery instruction' },
    ...Object.entries(record).flatMap(([field, child]) =>
      withField(child, key).map((changed) => ({ ...record, [field]: changed })),
    ),
  ];
}

describe('training outbound decision (LYB-281)', () => {
  let fixtures: Fixture[] = [];
  beforeAll(async () => {
    const now = new Date('2026-10-31T00:00:00Z');
    const h = revisionHarness();
    const proposed = await createInitialTrainingProposal({
      revisions: h.port,
      subject: 'owner',
      body: proposalBody,
      now,
    });
    if (proposed.kind !== 'stored') throw new Error(proposed.kind);
    const decided = await decideInitialTrainingProposal({
      revisions: h.port,
      subject: 'owner',
      body: decisionBody(proposed.stored.proposal.id),
      now,
    });
    if (decided.kind !== 'decided') throw new Error(decided.kind);
    fixtures = [
      { name: 'initial proposal', schema: initialProposalSchema, record: proposed.stored.proposal },
      { name: 'initial receipt', schema: revisionReceiptSchema, record: decided.receipt },
      { name: 'stored revision', schema: storedProposalSchema, record: proposed.stored },
    ];

    const delegated = revisionHarness();
    delegated.context.evidenceFingerprint = 'example-evidence';
    const result = await createDelegatedProposal({
      revisions: delegated.port,
      records: delegated.records,
      subject: 'owner',
      actor: { kind: 'user', subject: 'owner' },
      now,
      body: {
        ...proposalBody,
        intent: {
          kind: 'recommend',
          adultConfirmed: true,
          safetyConfirmed: true,
          inputs: {
            goal: 'Build muscle',
            experience: 'new',
            sessionsPerWeek: 2,
            minutesPerSession: 60,
            equipment: 'full_gym',
            excludedVariantIds: [],
            limitations: [],
            preferredVariantIds: [],
          },
        },
      },
    });
    if (result.kind !== 'stored') throw new Error(result.kind);
    fixtures = [
      ...fixtures,
      {
        name: 'delegated proposal',
        schema: delegatedProposalSchema,
        record: result.stored.proposal,
      },
      { name: 'stored delegated revision', schema: storedProposalSchema, record: result.stored },
      {
        name: 'delegated receipt',
        schema: delegatedReceiptSchema,
        record: {
          version: 2,
          proposalId: result.stored.proposal.id,
          requestId: proposalBody.requestId,
          decision: 'reject',
          status: 'rejected',
          actor: { kind: 'user', subject: 'owner' },
          priorState: null,
          revisionId: null,
          setup: null,
          decidedAt: now.toISOString(),
        },
      },
    ];

    const set = {
      sessionId: 'session',
      exerciseId: 'exercise',
      setNumber: 1,
      reps: 8,
      loadKg: 20,
      rir: 2,
    };
    const payloads = {
      read_plan: {
        sessionId: 'session',
        exercises: [
          {
            exerciseId: 'exercise',
            name: 'Example exercise',
            sets: 3,
            targetReps: 8,
            repRange: { min: 6, max: 10 },
            targetRir: 2,
            targetLoadKg: 20,
            evidenceIds: ['evidence'],
          },
        ],
      },
      log_set: set,
      log_check_in: { completed: true },
      read_progress: {
        sets: [set],
        lastUsedLoad: [{ exerciseId: 'exercise', loadKg: 20 }],
        checkInCompleted: true,
      },
    };
    fixtures = [
      ...fixtures,
      ...Object.entries(TRAINING_MCP_V1_ALLOWLIST).map(([name, schema]) => ({
        name,
        schema,
        record: payloads[name as keyof typeof payloads],
      })),
    ];
  });

  it('reads exactly one production policy across apps, packages and agent sources', () => {
    const root = resolve(process.cwd(), '../..');
    function collect(directory: string): Array<[string, string]> {
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
          ? [[file, readFileSync(resolve(root, file), 'utf8')] as [string, string]]
          : [];
      });
    }
    assertSinglePolicy(['apps', 'packages', 'agent'].flatMap(collect));
    expect(TRAINING_OUTBOUND_POLICY).toMatchObject({
      response: 'structured_records_only',
      coachMessage: false,
      notification: false,
      send: false,
    });
    expect(Object.isFrozen(TRAINING_OUTBOUND_POLICY)).toBe(true);
    expect(Object.isFrozen(TRAINING_OUTBOUND_POLICY.forbiddenFields)).toBe(true);
  }, 30_000);

  it('fails for a missing or duplicated policy, including renamed and JSON copies', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'src/lib/training/outbound-policy.ts'),
      'utf8',
    );
    const original: [string, string] = [canonical, source];
    expect(() => assertSinglePolicy([])).toThrow();
    assertSinglePolicy([original]);
    for (const copy of [
      source,
      source.replaceAll('TRAINING_OUTBOUND_POLICY', 'otherDecision'),
      JSON.stringify({
        response: 'structured_records_only',
        coachMessage: false,
        notification: false,
        send: false,
      }),
    ])
      expect(() => assertSinglePolicy([original, ['agent/second-policy.ts', copy]])).toThrow();
    expect(() => assertSinglePolicy([[canonical, `${source}\n${source}`]])).toThrow();
    assertSinglePolicy([
      original,
      ['agent/consumer.ts', "export { TRAINING_OUTBOUND_POLICY } from './policy';"],
    ]);
  });

  it('accepts structured revision and MCP response fixtures unchanged', () => {
    expect(fixtures).toHaveLength(10);
    for (const { name, schema, record } of fixtures)
      expect({ name, record: schema.parse(record) }).toEqual({ name, record });
  });

  it.each(forbiddenFields)('rejects %s at every response nesting level', (field) => {
    for (const { name, schema, record } of fixtures)
      for (const changed of withField(record, field))
        expect({ name, accepted: schema.safeParse(changed).success }).toEqual({
          name,
          accepted: false,
        });
  });

  it.each(['user', 'ChatGPT', 'Grok', 'Muse'])(
    'grants no outbound exception for %s',
    (recipient) => {
      for (const { schema, record } of fixtures)
        for (const field of ['message', 'notification', 'send'])
          for (const value of [null, false, { recipient, text: 'Coach message' }])
            expect(schema.safeParse({ ...(record as object), [field]: value }).success).toBe(false);
    },
  );
});
