#!/usr/bin/env node

import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const DEFAULT_ISSUER = 'https://jov.ie/api/auth';
const DEFAULT_CLIENT_ID = 'logyourbody-ios';
const DEFAULT_REDIRECT_URI = 'logyourbody://oauth';
const APPLE_AUTH_HOST = 'appleid.apple.com';
const PKCE_CHALLENGE = 'A'.repeat(43);

function requireStatus(response, expected, boundary) {
  if (response.status !== expected) {
    throw new Error(`${boundary} returned HTTP ${response.status}; expected ${expected}.`);
  }
}

function requireLocation(response, baseURL, boundary) {
  const location = response.headers.get('location');
  if (!location) {
    throw new Error(`${boundary} did not return a Location header.`);
  }
  return new URL(location, baseURL);
}

async function resolveIdentityURL(response, issuerOrigin) {
  if (response.status === 302) {
    return requireLocation(response, issuerOrigin, 'OAuth authorize');
  }
  if (response.status === 200) {
    const payload = await response.json();
    if (payload?.redirect === true && typeof payload.url === 'string') {
      return new URL(payload.url, issuerOrigin);
    }
  }
  throw new Error(`OAuth authorize returned HTTP ${response.status} without a redirect.`);
}

function requireStateCookie(response) {
  const setCookie = response.headers.get('set-cookie');
  const cookie = setCookie?.split(';', 1)[0];
  if (!cookie?.startsWith('__Secure-better-auth.state=')) {
    throw new Error('Apple provider start did not issue the Better Auth state cookie.');
  }
  return cookie;
}

async function captureLiveProviderRequest(identityURL) {
  const require = createRequire(new URL('../../apps/web/package.json', import.meta.url));
  const { chromium } = require('playwright');
  const browser = await chromium.launch({
    channel: process.env.PLAYWRIGHT_BROWSER_CHANNEL || 'chrome',
    headless: true,
  });

  try {
    const page = await browser.newPage();
    await page.goto(identityURL.toString(), { waitUntil: 'networkidle' });
    const providerRequest = page.waitForRequest((request) =>
      request.url().endsWith('/api/auth/sign-in/social'),
    );
    await page.getByRole('button', { name: 'Continue with Apple' }).click();
    const request = await providerRequest;
    return request.postDataJSON();
  } finally {
    await browser.close();
  }
}

export async function verifyIOSAuthContract({
  fetchImpl = fetch,
  captureProviderRequest = captureLiveProviderRequest,
  issuer = DEFAULT_ISSUER,
  clientID = DEFAULT_CLIENT_ID,
  redirectURI = DEFAULT_REDIRECT_URI,
  outerState = `ios-release-probe-${randomUUID()}`,
} = {}) {
  const normalizedIssuer = issuer.replace(/\/$/, '');
  const issuerURL = new URL(normalizedIssuer);
  if (issuerURL.protocol !== 'https:') {
    throw new Error('The production auth issuer must use HTTPS.');
  }

  const authorizeURL = new URL(`${normalizedIssuer}/oauth2/authorize`);
  authorizeURL.search = new URLSearchParams({
    response_type: 'code',
    client_id: clientID,
    redirect_uri: redirectURI,
    scope: 'openid profile email offline_access',
    state: outerState,
    code_challenge: PKCE_CHALLENGE,
    code_challenge_method: 'S256',
  }).toString();

  const authorizeResponse = await fetchImpl(authorizeURL, {
    redirect: 'manual',
    headers: { accept: 'text/html,application/xhtml+xml' },
  });
  const identityURL = await resolveIdentityURL(authorizeResponse, issuerURL.origin);
  if (identityURL.origin !== issuerURL.origin || identityURL.pathname !== '/identity') {
    throw new Error('OAuth authorize did not hand off to the production identity page.');
  }

  const providerRequest = await captureProviderRequest(identityURL);
  if (
    providerRequest?.provider !== 'apple' ||
    providerRequest?.oauth_query !== identityURL.searchParams.toString()
  ) {
    throw new Error('Live identity page did not preserve the signed native OAuth transaction.');
  }

  const socialResponse = await fetchImpl(new URL(`${normalizedIssuer}/sign-in/social`), {
    method: 'POST',
    redirect: 'manual',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      origin: issuerURL.origin,
      referer: identityURL.toString(),
    },
    body: JSON.stringify(providerRequest),
  });
  requireStatus(socialResponse, 200, 'Apple provider start');
  const stateCookie = requireStateCookie(socialResponse);
  const socialPayload = await socialResponse.json();
  const appleURL = new URL(socialPayload.url);
  const innerState = appleURL.searchParams.get('state');
  if (appleURL.host !== APPLE_AUTH_HOST || !innerState) {
    throw new Error('Apple provider start did not return a valid Apple authorization URL.');
  }

  const callbackProbeURL = new URL(`${normalizedIssuer}/callback/apple`);
  callbackProbeURL.search = new URLSearchParams({
    error: 'access_denied',
    state: innerState,
  }).toString();
  const callbackResponse = await fetchImpl(callbackProbeURL, {
    redirect: 'manual',
    headers: {
      accept: 'text/html',
      cookie: stateCookie,
    },
  });
  requireStatus(callbackResponse, 302, 'Apple callback');
  const callbackURL = requireLocation(callbackResponse, issuerURL.origin, 'Apple callback');
  const expectedRedirect = new URL(redirectURI);
  if (
    callbackURL.protocol !== expectedRedirect.protocol ||
    callbackURL.host !== expectedRedirect.host ||
    callbackURL.pathname !== expectedRedirect.pathname ||
    callbackURL.searchParams.get('error') !== 'access_denied' ||
    callbackURL.searchParams.get('state') !== outerState ||
    callbackURL.searchParams.get('iss') !== normalizedIssuer ||
    callbackURL.searchParams.has('error_description')
  ) {
    throw new Error('Apple callback did not safely return to the registered iOS redirect.');
  }

  return {
    authorizeStatus: authorizeResponse.status,
    identityPath: identityURL.pathname,
    providerHost: appleURL.host,
    callbackStatus: callbackResponse.status,
    callbackScheme: callbackURL.protocol,
    callbackHost: callbackURL.host,
  };
}

async function main() {
  const receipt = await verifyIOSAuthContract();
  console.log(
    [
      'iOS auth contract verified',
      `authorize=${receipt.authorizeStatus}`,
      `identity=${receipt.identityPath}`,
      `provider=${receipt.providerHost}`,
      `callback=${receipt.callbackStatus}`,
      `return=${receipt.callbackScheme}//${receipt.callbackHost}`,
    ].join(' '),
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`iOS auth contract failed: ${error.message}`);
    process.exitCode = 1;
  });
}
