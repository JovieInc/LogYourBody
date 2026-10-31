/** @jest-environment node */

import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';
import { z } from 'zod';
import { TRAINING_MCP_V1_ALLOWLIST } from './training-field-allowlist';

const canonical = 'apps/web/src/lib/mcp/training-field-allowlist.ts';
const operations = ['read_plan', 'log_set', 'log_check_in', 'read_progress'];

function definitions(sources: Array<[string, string]>): string[] {
  const found: string[] = [];
  for (const [file, source] of sources) {
    const tree = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
    function visit(node: ts.Node) {
      // Imports/re-exports are consumers. A declaration or copied operation map is a definition.
      if (
        ts.isVariableDeclaration(node) &&
        /training.*mcp.*allowlist|mcp.*training.*allowlist/i.test(node.name.getText(tree))
      ) {
        found.push(file);
        return;
      }
      if (ts.isObjectLiteralExpression(node)) {
        const keys = node.properties.map((property) =>
          property.name?.getText(tree).replace(/^['"]|['"]$/g, ''),
        );
        if (operations.every((operation) => keys.includes(operation))) {
          found.push(file);
          return;
        }
      }
      ts.forEachChild(node, visit);
    }
    visit(tree);
  }
  return found.sort();
}

function assertSingleDefinition(sources: Array<[string, string]>) {
  expect(definitions(sources)).toEqual([canonical]);
}

type FieldSchema = {
  properties?: Record<string, FieldSchema>;
  items?: FieldSchema;
  additionalProperties?: boolean;
};

function fieldPaths(schema: FieldSchema, prefix = ''): string[] {
  if (schema.items) return fieldPaths(schema.items, `${prefix}[]`);
  if (!schema.properties) return [];
  expect(schema.additionalProperties).toBe(false);
  return Object.entries(schema.properties).flatMap(([key, field]) => {
    const path = prefix ? `${prefix}.${key}` : key;
    return [path, ...fieldPaths(field, path)];
  });
}

const set = {
  sessionId: 'session-example',
  exerciseId: 'exercise-example',
  setNumber: 1,
  reps: 8,
  loadKg: 20,
  rir: 2,
  completedAt: '2026-10-31T00:00:00Z',
};
const plan = {
  sessionId: set.sessionId,
  exercises: [
    {
      exerciseId: set.exerciseId,
      name: 'Example exercise',
      sets: 3,
      targetReps: 8,
      repRange: { min: 6, max: 10 },
      targetRir: 2,
      targetLoadKg: 20,
      evidenceIds: ['evidence-example'],
    },
  ],
};
const payloads = {
  read_plan: plan,
  log_set: set,
  log_check_in: { completed: true },
  read_progress: {
    sets: [set],
    lastUsedLoad: [{ exerciseId: set.exerciseId, loadKg: 20 }],
    checkInCompleted: true,
  },
};
const forbiddenKeys = [
  'physique',
  'physiqueGoal',
  'recoveryNotes',
  'recovery_narrative',
  'bodyComposition',
  'bodyFatPercent',
  'bodyWeightKg',
  'leanMassKg',
  'medication',
  'medications',
  'glp1',
  'glp_1_dose',
  'painNotes',
  'pain_note',
  'jointPain',
  'location',
  'latitude',
  'longitude',
  'gps',
  'notes',
  'metadata',
];

describe('training-only MCP v1 field decision (LYB-279)', () => {
  it('has exactly one production allowlist across apps, packages and agent sources', () => {
    const root = resolve(process.cwd(), '../..');
    const sources: Array<[string, string]> = [];
    function collect(directory: string) {
      for (const entry of readdirSync(resolve(root, directory), { withFileTypes: true })) {
        const file = `${directory}/${entry.name}`;
        if (entry.isDirectory()) {
          if (
            !/^(?:node_modules|dist|build|coverage|Vendor|Pods|DerivedData|test_results|fixtures|__tests__|\..*)$/.test(
              entry.name,
            )
          )
            collect(file);
        } else if (
          entry.isFile() &&
          /\.(?:[cm]?[jt]sx?|json)$/.test(file) &&
          !/\.(?:test|spec|testing)\./.test(file)
        ) {
          sources.push([file, readFileSync(resolve(root, file), 'utf8')]);
        }
      }
    }
    for (const directory of ['apps', 'packages', 'agent']) collect(directory);
    assertSingleDefinition(sources);
  }, 30_000);

  it('fails if the allowlist is missing or copied, including a renamed definition', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'src/lib/mcp/training-field-allowlist.ts'),
      'utf8',
    );
    const original: [string, string] = [canonical, source];
    expect(() => assertSingleDefinition([])).toThrow();
    assertSingleDefinition([original]);
    expect(() => assertSingleDefinition([original, ['agent/second-policy.ts', source]])).toThrow();
    expect(() =>
      assertSingleDefinition([
        original,
        ['packages/other/policy.ts', source.replace('TRAINING_MCP_V1_ALLOWLIST', 'otherPolicy')],
      ]),
    ).toThrow();
    expect(() => assertSingleDefinition([[canonical, `${source}\n${source}`]])).toThrow();
    expect(() =>
      assertSingleDefinition([
        original,
        [
          'packages/other/policy.json',
          JSON.stringify(Object.fromEntries(operations.map((key) => [key, []]))),
        ],
      ]),
    ).toThrow();
  });

  it('locks all allowed keys, including nested objects and arrays', () => {
    expect(Object.keys(TRAINING_MCP_V1_ALLOWLIST)).toEqual(operations);
    const paths = Object.fromEntries(
      Object.entries(TRAINING_MCP_V1_ALLOWLIST).map(([operation, schema]) => [
        operation,
        fieldPaths(z.toJSONSchema(schema) as FieldSchema),
      ]),
    );
    const setKeys = [
      'sessionId',
      'exerciseId',
      'setNumber',
      'reps',
      'loadKg',
      'rir',
      'completedAt',
    ];
    expect(paths).toEqual({
      read_plan: [
        'sessionId',
        'exercises',
        'exercises[].exerciseId',
        'exercises[].name',
        'exercises[].sets',
        'exercises[].targetReps',
        'exercises[].repRange',
        'exercises[].repRange.min',
        'exercises[].repRange.max',
        'exercises[].targetRir',
        'exercises[].targetLoadKg',
        'exercises[].evidenceIds',
      ],
      log_set: setKeys,
      log_check_in: ['completed'],
      read_progress: [
        'sets',
        ...setKeys.map((key) => `sets[].${key}`),
        'lastUsedLoad',
        'lastUsedLoad[].exerciseId',
        'lastUsedLoad[].loadKg',
        'checkInCompleted',
      ],
    });
    for (const path of Object.values(paths).flat()) {
      expect(path.replace(/[_-]/g, '')).not.toMatch(
        /physique|recover|body|medicat|glp1|pain|location|latitude|longitude|gps|notes/i,
      );
    }
  });

  it.each(Object.entries(TRAINING_MCP_V1_ALLOWLIST))(
    'accepts allowed %s data and rejects unknown keys',
    (operation, schema) => {
      const payload = payloads[operation as keyof typeof payloads];
      expect(schema.parse(payload)).toEqual(payload);
      for (const key of forbiddenKeys) {
        expect(schema.safeParse({ ...payload, [key]: 'excluded' }).success).toBe(false);
      }
    },
  );

  it.each(forbiddenKeys)('rejects nested %s in plan and progress readbacks', (key) => {
    expect(
      TRAINING_MCP_V1_ALLOWLIST.read_plan.safeParse({
        ...plan,
        exercises: [{ ...plan.exercises[0], [key]: 'excluded' }],
      }).success,
    ).toBe(false);
    expect(
      TRAINING_MCP_V1_ALLOWLIST.read_plan.safeParse({
        ...plan,
        exercises: [{ ...plan.exercises[0], repRange: { min: 6, max: 10, [key]: 'excluded' } }],
      }).success,
    ).toBe(false);
    expect(
      TRAINING_MCP_V1_ALLOWLIST.read_progress.safeParse({
        ...payloads.read_progress,
        sets: [{ ...set, [key]: 'excluded' }],
      }).success,
    ).toBe(false);
    expect(
      TRAINING_MCP_V1_ALLOWLIST.read_progress.safeParse({
        ...payloads.read_progress,
        lastUsedLoad: [{ exerciseId: set.exerciseId, loadKg: 20, [key]: 'excluded' }],
      }).success,
    ).toBe(false);
  });

  it('allows only a boolean check-in completion value', () => {
    expect(TRAINING_MCP_V1_ALLOWLIST.log_check_in.parse({ completed: false })).toEqual({
      completed: false,
    });
    for (const completed of ['ready', { recoveryNotes: 'excluded' }, null, 1]) {
      expect(TRAINING_MCP_V1_ALLOWLIST.log_check_in.safeParse({ completed }).success).toBe(false);
    }
    expect(TRAINING_MCP_V1_ALLOWLIST.log_check_in.safeParse({}).success).toBe(false);
    expect(TRAINING_MCP_V1_ALLOWLIST.log_set.parse({ ...set, loadKg: null }).loadKg).toBeNull();
    expect(TRAINING_MCP_V1_ALLOWLIST.log_set.parse({ ...set, loadKg: 0 }).loadKg).toBe(0);
  });
});
