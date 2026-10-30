import { z } from 'zod';
import { LYB_MCP_SCOPES } from './contract';
import { HEALTH_VAULT_WIDGET_URI } from './health-vault/constants';
import { describeVaultSummary } from './health-vault/snapshot';
import { HEALTH_VAULT_SHARE_FIELDS } from './health-vault/types';
import type { McpToolDependencies, McpToolResult, ToolDefinition } from './tools';

const emptyInput = z.object({}).strict();
const shareInput = z
  .object({
    consentId: z.string().trim().min(8).max(200),
  })
  .strict();

const countSchema = { type: 'integer', minimum: 0 };
const seriesSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['first', 'last', 'delta', 'samples'],
  properties: {
    first: { type: 'number' },
    last: { type: 'number' },
    delta: { type: 'number' },
    samples: { type: 'integer', minimum: 1 },
  },
};
const unavailable = 'LogYourBody vault is unavailable right now. Try again shortly.';
const notShared = 'Nothing was shared. Confirm a summary in the LogYourBody vault view first.';

function text(message: string, structuredContent?: Record<string, unknown>): McpToolResult {
  return {
    content: [{ type: 'text', text: message }],
    ...(structuredContent ? { structuredContent } : {}),
  };
}

function failure(message: string): McpToolResult {
  return { content: [{ type: 'text', text: message }], isError: true };
}

function requireVault(deps: McpToolDependencies) {
  return deps.vault ? null : failure(unavailable);
}

export function healthVaultMcpTools(): ToolDefinition[] {
  return [
    {
      gate: 'vault',
      widgetOnly: true,
      name: 'open_health_vault',
      title: 'Open health vault',
      description:
        'Opens the user LogYourBody vault view of scans, progress photos, and weigh-ins. The result has readiness and counts only. Measurements stay in the view and are not in this result.',
      scope: LYB_MCP_SCOPES.vaultRead,
      readOnly: true,
      input: emptyInput,
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      outputSchema: {
        type: 'object',
        additionalProperties: false,
        required: ['vault', 'items'],
        properties: {
          vault: { type: 'string', enum: ['ready'] },
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['dexa', 'photos', 'weigh_ins'],
            properties: { dexa: countSchema, photos: countSchema, weigh_ins: countSchema },
          },
        },
      },
      ui: {
        resourceUri: HEALTH_VAULT_WIDGET_URI,
        visibility: ['model', 'app'],
      },
      openai: {
        'openai/outputTemplate': HEALTH_VAULT_WIDGET_URI,
        'openai/toolInvocation/invoking': 'Opening your vault',
        'openai/toolInvocation/invoked': 'Vault ready',
      },
      async run(subject, _args, deps) {
        const missing = requireVault(deps);
        if (missing || !deps.vault) return missing ?? failure(unavailable);
        const opened = await deps.vault.open(subject);
        if (!opened.ok) return failure(unavailable);
        return {
          content: [
            {
              type: 'text',
              text: 'Your LogYourBody vault is ready in the private view. This result has counts only.',
            },
          ],
          structuredContent: { vault: 'ready', items: opened.counts },
          _meta: { viewHandle: opened.handle },
        };
      },
    },
    {
      gate: 'vault',
      name: 'share_summary_with_chatgpt',
      title: 'Share a confirmed vault summary',
      description:
        'Returns a body-composition summary only after the user confirms the exact fields in the LogYourBody vault view. Without that confirmation, this returns nothing about scans, photos, or weigh-ins. Do not guess or invent measurements.',
      scope: LYB_MCP_SCOPES.vaultRead,
      readOnly: false,
      idempotent: false,
      input: shareInput,
      inputSchema: {
        type: 'object',
        additionalProperties: false,
        required: ['consentId'],
        properties: {
          consentId: {
            type: 'string',
            minLength: 8,
            maxLength: 200,
            description: 'Confirmation id from the vault view. Not a measurement.',
          },
        },
      },
      outputSchema: {
        type: 'object',
        additionalProperties: false,
        required: ['shared', 'summary'],
        properties: {
          shared: {
            type: 'array',
            items: { type: 'string', enum: [...HEALTH_VAULT_SHARE_FIELDS] },
          },
          summary: {
            type: 'object',
            additionalProperties: false,
            properties: {
              lean_mass: seriesSchema,
              body_fat: seriesSchema,
              weight: seriesSchema,
            },
          },
        },
      },
      ui: { visibility: ['model', 'app'] },
      openai: { 'openai/widgetAccessible': true },
      async run(subject, raw: z.infer<typeof shareInput>, deps) {
        const missing = requireVault(deps);
        if (missing || !deps.vault) return missing ?? failure(unavailable);
        const shared = await deps.vault.share(subject, raw.consentId);
        if (!shared.ok) return failure(notShared);
        const known = HEALTH_VAULT_SHARE_FIELDS.filter((field) => shared.fields.includes(field));
        return text(describeVaultSummary(shared.summary), {
          shared: known,
          summary: shared.summary,
        });
      },
    },
  ];
}
