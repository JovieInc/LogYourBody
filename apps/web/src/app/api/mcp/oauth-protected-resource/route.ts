import { mcpHandlers } from '../dependencies';

// Served at /.well-known/oauth-protected-resource/api/mcp (RFC 9728) and the origin-level
// alias through rewrites in next.config.ts.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const GET = mcpHandlers.metadata;
export const OPTIONS = mcpHandlers.options;
