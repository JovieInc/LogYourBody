import { z } from 'zod';
import {
  correctWeightEntry,
  createWeightEntry,
  deleteWeightEntry,
  listWeightEntries,
  type WeightActionResult,
  type WeightFailure,
  type ListWeightResult,
} from '@/lib/metrics/weight-lifecycle';
import {
  correctWeightBodySchema,
  createWeightBodySchema,
  deleteWeightBodySchema,
  listWeightQuerySchema,
} from '@/lib/metrics/weight-lifecycle';
import { LYB_MCP_SCOPES } from './contract';
import type { McpToolDependencies, McpToolResult, ToolDefinition } from './tools';

const uuid = { type: 'string', format: 'uuid' };
const measurement = {
  measured_at: { type: 'string', description: 'ISO-8601 timestamp with an explicit offset.' },
  utc_offset_minutes: { type: 'integer' },
  local_date: { type: 'string', description: 'Calendar date in iana_zone, YYYY-MM-DD.' },
  iana_zone: { type: 'string' },
};
const identity = {
  operation_id: uuid,
  record_id: uuid,
  subject: { type: 'string', description: 'Must match the token subject when sent.' },
  user_id: { type: 'string', description: 'Must match the token subject when sent.' },
};

function text(
  message: string,
  structuredContent?: Record<string, unknown>,
  isError = false,
): McpToolResult {
  return {
    content: [{ type: 'text', text: message }],
    ...(structuredContent ? { structuredContent } : {}),
    ...(isError ? { isError: true } : {}),
  };
}

function rejected(failure: WeightFailure): McpToolResult {
  return text(
    `Weight request rejected (${failure.code}).`,
    {
      code: failure.code,
      reason: failure.reason ?? null,
    },
    true,
  );
}

function saved(result: WeightActionResult): McpToolResult {
  if (!result.ok) return rejected(result);
  const message = result.replayed
    ? 'Replayed the original weight receipt. Apple Health was not changed.'
    : 'Saved the weight entry in LogYourBody. Apple Health was not changed.';
  return text(message, { replayed: result.replayed, receipt: result.receipt });
}

function listed(result: ListWeightResult): McpToolResult {
  if (!result.ok) return rejected(result);
  return text(
    result.records.length ? `Found ${result.records.length} weight entries.` : 'No weight entries.',
    { records: result.records, next_cursor: result.next_cursor },
  );
}

function requireStore(deps: McpToolDependencies) {
  if (!deps.weight)
    return text('LogYourBody weight is unavailable right now. Try again shortly.', undefined, true);
  return null;
}

export function weightMcpTools(): ToolDefinition[] {
  const tools: ToolDefinition[] = [
    {
      gate: 'metrics',
      name: 'create_weight_entry',
      title: 'Create weight entry',
      description:
        'Create one manual weight entry for the connected user. value and unit must be explicit kg or lb. A repeated operation_id returns the original receipt. This does not write Apple Health.',
      scope: LYB_MCP_SCOPES.metricsWrite,
      readOnly: false,
      idempotent: true,
      input: createWeightBodySchema as unknown as z.ZodType<Record<string, unknown>>,
      inputSchema: {
        type: 'object',
        properties: {
          ...identity,
          value: { type: 'number' },
          unit: { type: 'string', enum: ['kg', 'lb'] },
          ...measurement,
        },
        required: [
          'operation_id',
          'record_id',
          'value',
          'unit',
          'measured_at',
          'utc_offset_minutes',
          'local_date',
          'iana_zone',
        ],
        additionalProperties: false,
      },
      async run(subject, args, deps) {
        const missing = requireStore(deps);
        if (missing || !deps.weight)
          return missing ?? text('LogYourBody weight is unavailable right now.', undefined, true);
        return saved(
          await createWeightEntry({
            gateEnabled: true,
            subject,
            body: args,
            store: deps.weight,
            now: deps.now(),
          }),
        );
      },
    },
    {
      gate: 'metrics',
      name: 'list_weight_entries',
      title: 'List weight entries',
      description:
        "List the connected user's weight entries, newest first. Pass record_id to read one row, including a tombstone. This does not read another person's data.",
      scope: LYB_MCP_SCOPES.metricsRead,
      readOnly: true,
      input: listWeightQuerySchema as unknown as z.ZodType<Record<string, unknown>>,
      inputSchema: {
        type: 'object',
        properties: {
          cursor: { type: 'string' },
          limit: { type: 'integer', minimum: 1, maximum: 100 },
          record_id: uuid,
          subject: { type: 'string' },
          user_id: { type: 'string' },
        },
        additionalProperties: false,
      },
      async run(subject, args, deps) {
        const missing = requireStore(deps);
        if (missing || !deps.weight)
          return missing ?? text('LogYourBody weight is unavailable right now.', undefined, true);
        return listed(
          await listWeightEntries({
            gateEnabled: true,
            subject,
            query: args,
            store: deps.weight,
          }),
        );
      },
    },
    {
      gate: 'metrics',
      name: 'correct_weight_entry',
      title: 'Correct weight entry',
      description:
        'Correct one owned weight entry. expected_revision must be the current revision. A stale revision conflicts and does not create a new row. This does not write Apple Health.',
      scope: LYB_MCP_SCOPES.metricsWrite,
      readOnly: false,
      idempotent: true,
      input: correctWeightBodySchema as unknown as z.ZodType<Record<string, unknown>>,
      inputSchema: {
        type: 'object',
        properties: {
          ...identity,
          value: { type: 'number' },
          unit: { type: 'string', enum: ['kg', 'lb'] },
          ...measurement,
          expected_revision: { type: 'integer', minimum: 1 },
        },
        required: [
          'operation_id',
          'record_id',
          'value',
          'unit',
          'measured_at',
          'utc_offset_minutes',
          'local_date',
          'iana_zone',
          'expected_revision',
        ],
        additionalProperties: false,
      },
      async run(subject, args, deps) {
        const missing = requireStore(deps);
        if (missing || !deps.weight)
          return missing ?? text('LogYourBody weight is unavailable right now.', undefined, true);
        return saved(
          await correctWeightEntry({
            gateEnabled: true,
            subject,
            body: args,
            store: deps.weight,
            now: deps.now(),
          }),
        );
      },
    },
    {
      gate: 'metrics',
      name: 'delete_weight_entry',
      title: 'Delete weight entry',
      description:
        'Tombstone one owned weight entry. expected_revision must match. Repeating the same operation_id returns the original receipt. This does not delete an Apple Health sample.',
      scope: LYB_MCP_SCOPES.metricsWrite,
      readOnly: false,
      destructive: true,
      idempotent: true,
      input: deleteWeightBodySchema as unknown as z.ZodType<Record<string, unknown>>,
      inputSchema: {
        type: 'object',
        properties: {
          ...identity,
          expected_revision: { type: 'integer', minimum: 1 },
        },
        required: ['operation_id', 'record_id', 'expected_revision'],
        additionalProperties: false,
      },
      async run(subject, args, deps) {
        const missing = requireStore(deps);
        if (missing || !deps.weight)
          return missing ?? text('LogYourBody weight is unavailable right now.', undefined, true);
        return saved(
          await deleteWeightEntry({
            gateEnabled: true,
            subject,
            body: args,
            store: deps.weight,
            now: deps.now(),
          }),
        );
      },
    },
  ];
  return tools;
}
