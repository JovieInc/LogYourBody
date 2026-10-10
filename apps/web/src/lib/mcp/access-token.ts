import { createPublicKey, verify, type JsonWebKey } from 'node:crypto';

export type AccessTokenPrincipal = {
  subject: string;
  scopes: ReadonlySet<string>;
  clientId: string | null;
};

type Jwk = JsonWebKey & { kid?: string; alg?: string; use?: string };

export type JwksSource = {
  /** Returns cached keys; `refresh` forces one refetch for key rotation. */
  keys(refresh?: boolean): Promise<Jwk[]>;
};

const CLOCK_SKEW_SECONDS = 30;

function decodeSegment(segment: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

/** Caches the issuer JWKS for `ttlMs` and refetches at most once per unknown `kid`. */
export function createJwksSource(input: {
  url: string;
  fetchImpl?: typeof fetch;
  ttlMs?: number;
  now?: () => number;
}): JwksSource {
  const fetchImpl = input.fetchImpl ?? fetch;
  const ttlMs = input.ttlMs ?? 10 * 60 * 1000;
  const now = input.now ?? Date.now;
  let cached: { keys: Jwk[]; at: number } | null = null;
  return {
    async keys(refresh = false) {
      if (!refresh && cached && now() - cached.at < ttlMs) return cached.keys;
      const response = await fetchImpl(input.url, { cache: 'no-store' });
      if (!response.ok) throw new Error('jwks_unavailable');
      const body = (await response.json()) as { keys?: unknown };
      const keys = Array.isArray(body.keys) ? (body.keys as Jwk[]) : [];
      cached = { keys, at: now() };
      return keys;
    },
  };
}

function signatureValid(signingInput: string, signature: string, jwk: Jwk): boolean {
  if (jwk.kty !== 'OKP' || jwk.crv !== 'Ed25519') return false;
  try {
    const key = createPublicKey({ key: jwk, format: 'jwk' });
    return verify(null, Buffer.from(signingInput), key, Buffer.from(signature, 'base64url'));
  } catch {
    return false;
  }
}

/**
 * Verifies a Jovie issuer access token for this resource: EdDSA signature against the
 * issuer JWKS, exact issuer, audience containing the resource URL, and time bounds.
 * Returns null on any failure so callers can only answer with a bearer challenge.
 */
export async function verifyAccessToken(
  token: string,
  input: { issuer: string; audience: string; jwks: JwksSource; nowSeconds: number },
): Promise<AccessTokenPrincipal | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [headerSegment, payloadSegment, signature] = parts as [string, string, string];
  const header = decodeSegment(headerSegment);
  const claims = decodeSegment(payloadSegment);
  if (!header || !claims || header.alg !== 'EdDSA' || header.crit !== undefined) return null;

  const kid = typeof header.kid === 'string' ? header.kid : null;
  const pick = (keys: Jwk[]) => keys.filter((key) => (kid ? key.kid === kid : true));
  let candidates: Jwk[];
  try {
    candidates = pick(await input.jwks.keys());
    if (candidates.length === 0 && kid) candidates = pick(await input.jwks.keys(true));
  } catch {
    return null;
  }
  const signingInput = `${headerSegment}.${payloadSegment}`;
  if (!candidates.some((key) => signatureValid(signingInput, signature, key))) return null;

  if (claims.iss !== input.issuer) return null;
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(input.audience)) return null;
  if (typeof claims.exp !== 'number' || claims.exp + CLOCK_SKEW_SECONDS <= input.nowSeconds)
    return null;
  if (typeof claims.nbf === 'number' && claims.nbf - CLOCK_SKEW_SECONDS > input.nowSeconds)
    return null;
  if (typeof claims.sub !== 'string' || !claims.sub) return null;

  const scope = typeof claims.scope === 'string' ? claims.scope : '';
  return {
    subject: claims.sub,
    scopes: new Set(scope.split(' ').filter(Boolean)),
    clientId:
      typeof claims.azp === 'string'
        ? claims.azp
        : typeof claims.client_id === 'string'
          ? claims.client_id
          : null,
  };
}
