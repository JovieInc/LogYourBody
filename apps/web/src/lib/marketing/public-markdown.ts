import { logYourBody } from '@jovieinc/product-registry';

export const PUBLIC_MARKDOWN_GATE = 'lyb_public_markdown_v1';
export const PUBLIC_MARKDOWN_HEADER = 'x-lyb-public-markdown';

/**
 * The browser analytics adapter intentionally returns false on the server.
 * Use Statsig's HTTP check with the existing public SDK key, failing closed.
 * Each evaluation is anonymous: no URL, account, cookies, IP or user-agent.
 */
export async function publicMarkdownEnabled(): Promise<boolean> {
  const key = process.env.NEXT_PUBLIC_STATSIG_CLIENT_KEY;
  const tier = process.env.NEXT_PUBLIC_STATSIG_ENV_TIER;
  if (!key || !tier || !['production', 'staging', 'development'].includes(tier)) return false;
  if (process.env.VERCEL_ENV === 'production' && tier !== 'production') return false;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 300);
  try {
    const response = await fetch(logYourBody.endpoints.vendor.statsig.gateEvaluationUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'statsig-api-key': key },
      body: JSON.stringify({
        gateName: PUBLIC_MARKDOWN_GATE,
        user: { userID: crypto.randomUUID(), statsigEnvironment: { tier } },
      }),
      signal: controller.signal,
      cache: 'no-store',
      redirect: 'error',
    });
    if (!response.ok) return false;
    const decision: unknown = await response.json();
    return (
      typeof decision === 'object' &&
      decision !== null &&
      'name' in decision &&
      decision.name === PUBLIC_MARKDOWN_GATE &&
      'value' in decision &&
      decision.value === true
    );
  } catch {
    return false;
  } finally {
    clearTimeout(timeout);
  }
}

export function homepageMarkdown(): string {
  const product = logYourBody;
  return (
    [
      '# ' + product.identity.name,
      product.brand.promise,
      product.brand.description,
      '## ' + product.messages.landing.headline,
      product.messages.landing.subheading,
      '## Public pages',
      [
        '- [Home](' + product.links.home + ')',
        '- [Support](' + product.links.support + ')',
        '- [Privacy](' + product.links.privacy + ')',
        '- [Terms](' + product.links.terms + ')',
      ].join('\n'),
    ].join('\n\n') + '\n'
  );
}

export function missingPageMarkdown(): string {
  return (
    [
      '# Page not found',
      'This public page is unavailable. Return to the homepage or contact support.',
      '- [Home](' + logYourBody.links.home + ')\n- [Support](' + logYourBody.links.support + ')',
    ].join('\n\n') + '\n'
  );
}

export function markdownResponse(body: string, status: 200 | 404, method: string): Response {
  return new Response(method === 'HEAD' ? null : body, {
    status,
    headers: {
      'Content-Type': 'text/markdown; charset=utf-8',
      Vary: 'Accept',
      'Cache-Control': 'private, no-store',
      ...(status === 404 ? { 'X-Robots-Tag': 'noindex' } : {}),
    },
  });
}
