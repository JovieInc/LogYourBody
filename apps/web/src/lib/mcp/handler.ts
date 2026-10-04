import type { ChatRateLimitResult } from '@/lib/ports/chat-conversations';
import type { AccessTokenPrincipal } from './access-token';
import { bearerChallenge, LYB_MCP_PROTOCOL_VERSIONS, LYB_MCP_SERVER_INFO } from './contract';
import { findTool, listTools, type McpToolDependencies } from './tools';

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
    case 'initialize':
      return {
        status: 200,
        body: rpcOk(id, {
          protocolVersion: negotiateVersion(message.params),
          capabilities: { tools: { listChanged: false } },
          serverInfo: LYB_MCP_SERVER_INFO,
          instructions: INSTRUCTIONS,
        }),
      };
    case 'ping':
      return { status: 200, body: rpcOk(id, {}) };
    case 'tools/list':
      return { status: 200, body: rpcOk(id, { tools: listTools() }) };
    case 'tools/call':
      return { status: 200, body: rpcOk(id, await callTool(message.params, principal, deps)) };
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
  if (!tool) return { content: [{ type: 'text', text: 'Unknown tool.' }], isError: true };
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
  } catch {
    return {
      content: [
        { type: 'text', text: 'LogYourBody training is unavailable right now. Try again shortly.' },
      ],
      isError: true,
    };
  }
}
