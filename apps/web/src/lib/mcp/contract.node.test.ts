/** @jest-environment node */

import { oauthIssuer } from '@/lib/auth/jovie-oauth';
import { endpoints } from '@/lib/generated/endpoints.generated';
import { LYB_MCP_SCOPES, LYB_TRAINING_MCP_SCOPES, protectedResourceMetadata } from './contract';

jest.mock('server-only', () => ({}));

describe('training MCP OAuth contract (LYB-280)', () => {
  it('allows exactly the two training scopes', () => {
    expect(Object.values(LYB_TRAINING_MCP_SCOPES)).toEqual([
      'lyb:training.read',
      'lyb:training.write',
    ]);
    expect(LYB_MCP_SCOPES.trainingRead).toBe('lyb:training.read');
    expect(LYB_MCP_SCOPES.trainingWrite).toBe('lyb:training.write');
  });

  it('advertises only training scopes and the existing Jovie issuer by default', () => {
    const previous = process.env.JOVIE_AUTH_ISSUER;
    try {
      delete process.env.JOVIE_AUTH_ISSUER;
      const metadata = protectedResourceMetadata({
        resourceUrl: 'https://www.logyourbody.com/api/mcp',
        issuer: oauthIssuer(),
      });
      expect(metadata.authorization_servers).toEqual([endpoints.auth.issuer]);
      expect(metadata.scopes_supported).toEqual(['lyb:training.read', 'lyb:training.write']);
    } finally {
      if (previous === undefined) delete process.env.JOVIE_AUTH_ISSUER;
      else process.env.JOVIE_AUTH_ISSUER = previous;
    }
  });
});
