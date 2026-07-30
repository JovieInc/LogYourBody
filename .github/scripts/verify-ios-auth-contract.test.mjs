import assert from 'node:assert/strict';
import test from 'node:test';
import { verifyIOSAuthContract } from './verify-ios-auth-contract.mjs';

const ISSUER = 'https://jov.ie/api/auth';
const OUTER_STATE = 'ios-release-probe-test';
const APPLE_PROVIDER_HOST = 'appleid.apple.com';
const INVALID_PROVIDER_HOST = 'provider.invalid';
const SIGNED_IDENTITY_QUERY = new URLSearchParams([
  ['response_type', 'code'],
  ['redirect_uri', 'logyourbody://oauth'],
  ['scope', 'openid profile email offline_access'],
  ['state', OUTER_STATE],
  ['client_id', 'logyourbody-ios'],
  ['code_challenge', 'A'.repeat(43)],
  ['code_challenge_method', 'S256'],
  ['exp', '2000000000'],
  ['ba_param', 'state'],
  ['ba_param', 'sig'],
  ['sig', 'signed'],
]).toString();

function response(status, { body, headers = {} } = {}) {
  return new Response(body, { status, headers });
}

function makeFetch({ callbackLocation, providerURL } = {}) {
  const requests = [];
  const fetchImpl = async (input, init = {}) => {
    const url = new URL(input);
    requests.push({ url, init });

    if (url.pathname.endsWith('/oauth2/authorize')) {
      return response(302, {
        headers: { location: `/identity?${SIGNED_IDENTITY_QUERY}` },
      });
    }

    if (url.pathname.endsWith('/sign-in/social')) {
      const body = JSON.parse(init.body);
      assert.equal(body.provider, 'apple');
      assert.equal(body.oauth_query, SIGNED_IDENTITY_QUERY);
      return response(200, {
        body: JSON.stringify({
          url: providerURL ?? `https://${APPLE_PROVIDER_HOST}/auth/authorize?state=inner-state`,
          redirect: true,
        }),
        headers: {
          'content-type': 'application/json',
          'set-cookie': '__Secure-better-auth.state=signed-state; Path=/; HttpOnly; Secure',
        },
      });
    }

    assert.equal(url.pathname, '/api/auth/callback/apple');
    assert.equal(url.searchParams.get('error'), 'access_denied');
    assert.equal(url.searchParams.get('state'), 'inner-state');
    assert.equal(init.headers.cookie, '__Secure-better-auth.state=signed-state');
    return response(302, {
      headers: {
        location:
          callbackLocation ??
          `logyourbody://oauth?error=access_denied&state=${OUTER_STATE}&iss=${encodeURIComponent(ISSUER)}`,
      },
    });
  };

  return { fetchImpl, requests };
}

const captureProviderRequest = async () => ({
  provider: 'apple',
  oauth_query: SIGNED_IDENTITY_QUERY,
});

test('proves the production-like authorize, Apple, and native callback contract', async () => {
  const { fetchImpl, requests } = makeFetch();

  const receipt = await verifyIOSAuthContract({
    fetchImpl,
    captureProviderRequest,
    outerState: OUTER_STATE,
  });

  assert.deepEqual(receipt, {
    authorizeStatus: 302,
    identityPath: '/identity',
    providerHost: 'appleid.apple.com',
    callbackStatus: 302,
    callbackScheme: 'logyourbody:',
    callbackHost: 'oauth',
  });
  assert.equal(requests.length, 3);
});

test('fails when the provider callback strands the user on the web error page', async () => {
  const { fetchImpl } = makeFetch({
    callbackLocation: `${ISSUER}/error?error=access_denied`,
  });

  await assert.rejects(
    verifyIOSAuthContract({
      fetchImpl,
      captureProviderRequest,
      outerState: OUTER_STATE,
    }),
    /did not safely return to the registered iOS redirect/,
  );
});

test('fails when the configured provider does not hand off to Apple', async () => {
  const { fetchImpl } = makeFetch({
    providerURL: `https://${INVALID_PROVIDER_HOST}/authorize?state=inner-state`,
  });

  await assert.rejects(
    verifyIOSAuthContract({
      fetchImpl,
      captureProviderRequest,
      outerState: OUTER_STATE,
    }),
    /did not return a valid Apple authorization URL/,
  );
});

test('fails when the live identity page drops the native OAuth transaction', async () => {
  const { fetchImpl } = makeFetch();

  await assert.rejects(
    verifyIOSAuthContract({
      fetchImpl,
      captureProviderRequest: async () => ({ provider: 'apple' }),
      outerState: OUTER_STATE,
    }),
    /did not preserve the signed native OAuth transaction/,
  );
});
