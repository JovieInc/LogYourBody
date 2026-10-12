/**
 * Public contract for the LogYourBody MCP server used by ChatGPT, Grok and other
 * remote MCP clients. The Jovie issuer must mint access tokens whose `aud` is the
 * resource URL below and whose `scope` carries the LYB scopes a tool needs.
 */
export const LYB_MCP_PATH = '/api/mcp';
export const LYB_MCP_PROTECTED_RESOURCE_METADATA_PATH =
  '/.well-known/oauth-protected-resource/api/mcp';

export const LYB_MCP_SCOPES = {
  trainingRead: 'lyb:training.read',
  trainingWrite: 'lyb:training.write',
} as const;
export type LybMcpScope = (typeof LYB_MCP_SCOPES)[keyof typeof LYB_MCP_SCOPES];

export const LYB_MCP_SERVER_INFO = { name: 'logyourbody', title: 'LogYourBody', version: '1.0.0' };
export const LYB_MCP_PROTOCOL_VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26'] as const;

/** Production pins the canonical API host; other environments use the request origin. */
export function mcpResourceUrl(requestOrigin: string, canonicalApiOrigin: string | null): string {
  return `${(canonicalApiOrigin ?? requestOrigin).replace(/\/$/, '')}${LYB_MCP_PATH}`;
}

export function protectedResourceMetadataUrl(resourceUrl: string): string {
  const url = new URL(resourceUrl);
  return `${url.origin}${LYB_MCP_PROTECTED_RESOURCE_METADATA_PATH}`;
}

export function protectedResourceMetadata(input: { resourceUrl: string; issuer: string }) {
  return {
    resource: input.resourceUrl,
    authorization_servers: [input.issuer],
    scopes_supported: [LYB_MCP_SCOPES.trainingRead, LYB_MCP_SCOPES.trainingWrite],
    bearer_methods_supported: ['header'],
    resource_name: 'LogYourBody',
    resource_documentation: `${new URL(input.resourceUrl).origin}/support`,
  };
}

export function bearerChallenge(input: {
  resourceUrl: string;
  error?: 'invalid_token' | 'insufficient_scope';
  scope?: string;
}): string {
  const parts = [`resource_metadata="${protectedResourceMetadataUrl(input.resourceUrl)}"`];
  if (input.error) parts.push(`error="${input.error}"`);
  if (input.scope) parts.push(`scope="${input.scope}"`);
  return `Bearer ${parts.join(', ')}`;
}
