import { TrainingMutationError } from '@/lib/training/mutation-admission';
import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { AccessTokenPrincipal } from './access-token';
import { bearerChallenge, LYB_MCP_PROTOCOL_VERSIONS, LYB_MCP_SERVER_INFO } from './contract';
import {
  HEALTH_VAULT_MODEL_INSTRUCTIONS,
  HEALTH_VAULT_WIDGET_URI,
  isHealthVaultWidgetSurface,
} from './health-vault/constants';
import { healthVaultResourceDescriptor, healthVaultWidgetResource } from './health-vault/widget';
import { findTool, listTools } from './list-tools';
import type { McpToolDependencies } from './tools';

type JsonRpcId = string | number | null;

export type McpHttpResult = {
  status: number;
  body: unknown;
  headers?: Record<string, string>;
};

export type McpHandlerDependencies = McpToolDependencies & {
  resourceUrl: string;
  reserveRequest: (subject: string) => Promise<ChatRateLimitResult>;
};

const rpcOk = (id: JsonRpcId, result: unknown) => ({ jsonrpc: '2.0' as const, id, result });
const rpcError = (id: JsonRpcId, code: number, message: string) => ({
  jsonrpc: '2.0' as const,
  id,
  error: { code, message },
});

const INSTRUCTIONS =
  'LogYourBody logs hypertrophy training. Use get_todays_workout before logging so exercise names match the plan. Repeat engine numbers exactly; never invent sets, reps, loads or reps in reserve. Do not give medical advice.';

const WEIGHT_INSTRUCTIONS =
  "Manual weight tools change only this user's weight entries. A receipt does not mean Apple Health was changed.";

function instructionsFor(deps: McpHandlerDependencies): string {
  const parts = [INSTRUCTIONS];
  if (deps.metricsEnabled?.() === true) parts.push(WEIGHT_INSTRUCTIONS);
  if (deps.vaultEnabled?.() === true) parts.push(HEALTH_VAULT_MODEL_INSTRUCTIONS);
  return parts.join(' ');
}

function toolListOptions(principal: AccessTokenPrincipal, deps: McpHandlerDependencies) {
  return {
    vault: deps.vaultEnabled?.() === true,
    widgetSurface: isHealthVaultWidgetSurface(principal.clientId),
  };
}

function negotiateVersion(params: unknown): string {
  const requested = (params as { protocolVersion?: unknown } | null)?.protocolVersion;
  return typeof requested === 'string' &&
    (LYB_MCP_PROTOCOL_VERSIONS as readonly string[]).includes(requested)
    ? requested
    : LYB_MCP_PROTOCOL_VERSIONS[0];
}

export function unauthenticatedResult(resourceUrl: string, error?: 'invalid_token'): McpHttpResult {
  return {
    status: 401,
    body: rpcError(null, -32001, 'Authentication required'),
    headers: { 'www-authenticate': bearerChallenge({ resourceUrl, error }) },
  };
}

export async function handleMcpRequest(input: {
  body: unknown;
  principal: AccessTokenPrincipal;
  deps: McpHandlerDependencies;
}): Promise<McpHttpResult> {
  const { body, principal, deps } = input;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return { status: 400, body: rpcError(null, -32700, 'Parse error') };
  }
  const message = body as { jsonrpc?: unknown; id?: unknown; method?: unknown; params?: unknown };
  const id: JsonRpcId =
    typeof message.id === 'string' || typeof message.id === 'number' ? message.id : null;
  if (message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
    return { status: 400, body: rpcError(id, -32600, 'Invalid request') };
  }
  // Notifications and client responses carry no id and get no body.
  if (message.id === undefined) return { status: 202, body: null };

  switch (message.method) {
    case 'initialize': {
      const vaultOn = deps.vaultEnabled?.() === true;
      return {
        status: 200,
        body: rpcOk(id, {
          protocolVersion: negotiateVersion(message.params),
          capabilities: vaultOn
            ? { tools: { listChanged: false }, resources: { listChanged: false } }
            : { tools: { listChanged: false } },
          serverInfo: LYB_MCP_SERVER_INFO,
          instructions: instructionsFor(deps),
        }),
      };
    }
    case 'ping':
      return { status: 200, body: rpcOk(id, {}) };
    case 'tools/list':
      return {
        status: 200,
        body: rpcOk(id, {
          tools: listTools(
            deps.delegatedEnabled?.() === true,
            deps.metricsEnabled?.() === true,
            toolListOptions(principal, deps),
          ),
        }),
      };
    case 'tools/call':
      return { status: 200, body: rpcOk(id, await callTool(message.params, principal, deps)) };
    case 'resources/list':
      return {
        status: 200,
        body: rpcOk(id, {
          resources: deps.vaultEnabled?.() === true ? [healthVaultResourceDescriptor()] : [],
        }),
      };
    case 'resources/read': {
      const uri = (message.params as { uri?: unknown } | null)?.uri;
      if (deps.vaultEnabled?.() !== true || uri !== HEALTH_VAULT_WIDGET_URI) {
        return { status: 200, body: rpcError(id, -32002, 'Resource not found') };
      }
      const resource = healthVaultWidgetResource(new URL(deps.resourceUrl).origin);
      return {
        status: 200,
        body: rpcOk(id, {
          contents: [
            {
              uri: resource.uri,
              mimeType: resource.mimeType,
              text: resource.text,
              _meta: resource._meta,
            },
          ],
        }),
      };
    }
    default:
      return { status: 200, body: rpcError(id, -32601, 'Method not found') };
  }
}

async function callTool(
  params: unknown,
  principal: AccessTokenPrincipal,
  deps: McpHandlerDependencies,
) {
  const { name, arguments: args } = (params ?? {}) as { name?: unknown; arguments?: unknown };
  const tool = findTool(name);
  const widgetSurface = isHealthVaultWidgetSurface(principal.clientId);
  // A widget-only tool on a client without a widget is unknown, not a scope error.
  if (
    !tool ||
    (tool.gate === 'metrics' && deps.metricsEnabled?.() !== true) ||
    (tool.gate === 'vault' && deps.vaultEnabled?.() !== true) ||
    (tool.widgetOnly === true && !widgetSurface)
  ) {
    return { content: [{ type: 'text', text: 'Unknown tool.' }], isError: true };
  }
  if (!principal.scopes.has(tool.scope)) {
    return {
      content: [
        {
          type: 'text',
          text: 'LogYourBody needs permission for this. Reconnect the app to grant it.',
        },
      ],
      isError: true,
      _meta: {
        'mcp/www_authenticate': [
          bearerChallenge({
            resourceUrl: deps.resourceUrl,
            error: 'insufficient_scope',
            scope: tool.scope,
          }),
        ],
      },
    };
  }
  const parsed = tool.input.safeParse(args ?? {});
  if (!parsed.success) {
    const fields = parsed.error.issues.map((issue) => issue.path.join('.') || 'input').join(', ');
    return { content: [{ type: 'text', text: `Invalid input: ${fields}.` }], isError: true };
  }
  const limited = await deps.reserveRequest(principal.subject);
  if (!limited.allowed) {
    return {
      content: [
        {
          type: 'text',
          text: `Too many requests. Try again in ${limited.retryAfterSeconds} seconds.`,
        },
      ],
      isError: true,
    };
  }
  try {
    return await tool.run(principal.subject, parsed.data as never, deps);
  } catch (error) {
    if (tool.gate === 'vault') {
      return {
        content: [
          { type: 'text', text: 'LogYourBody vault is unavailable right now. Try again shortly.' },
        ],
        isError: true,
      };
    }
    if (tool.gate === 'metrics') {
      return {
        content: [
          { type: 'text', text: 'LogYourBody weight is unavailable right now. Try again shortly.' },
        ],
        isError: true,
      };
    }
    if (error instanceof TrainingMutationError && error.code === 'training_context_changed')
      return {
        isError: true,
        structuredContent: { code: error.code },
        content: [
          {
            type: 'text',
            text: 'Training changed while this request was in flight. Read your current workout before retrying.',
          },
        ],
      };
    return {
      content: [
        { type: 'text', text: 'LogYourBody training is unavailable right now. Try again shortly.' },
      ],
      isError: true,
    };
  }
}
