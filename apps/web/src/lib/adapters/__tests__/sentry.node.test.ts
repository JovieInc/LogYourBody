/** @jest-environment node */
import * as Sentry from '@sentry/nextjs';
import {
  captureSyntheticError,
  initSentry,
  redactSentryEvent,
  sentryRuntimeConfig,
} from '../sentry';

describe('sentry adapter', () => {
  afterEach(async () => {
    Sentry.setUser(null);
    await Sentry.close();
  });

  it('stays off without a DSN', () => {
    expect(initSentry({})).toBe(false);
    expect(sentryRuntimeConfig({}).dsn).toBeUndefined();
  });

  it('reads release and environment from config', () => {
    expect(
      sentryRuntimeConfig({
        NEXT_PUBLIC_SENTRY_DSN: 'https://k@o0.ingest.sentry.io/1',
        NEXT_PUBLIC_SENTRY_RELEASE: 'abc123',
        VERCEL_ENV: 'production',
      }),
    ).toEqual({
      dsn: 'https://k@o0.ingest.sentry.io/1',
      release: 'abc123',
      environment: 'production',
    });
  });

  it('uses the public deployment environment in the browser', () => {
    expect(
      sentryRuntimeConfig({ NEXT_PUBLIC_VERCEL_ENV: 'preview', NODE_ENV: 'production' })
        .environment,
    ).toBe('preview');
  });

  it('disables automatic sensitive data collection with the installed SDK', () => {
    initSentry({ dsn: 'https://k@o0.ingest.sentry.io/1' });
    expect(Sentry.getClient()?.getOptions().dataCollection).toEqual({
      userInfo: false,
      cookies: false,
      httpHeaders: false,
      httpBodies: [],
      urlQueryParams: false,
      genAI: { inputs: false, outputs: false },
      mcp: { inputs: false, outputs: false },
      graphQL: { document: false, variables: false },
      databaseQueryData: false,
      queues: false,
      stackFrameVariables: false,
    });
  });

  it('strips user, cookies, bodies and credential headers', () => {
    const event = redactSentryEvent({
      type: undefined,
      user: { id: 'u', email: 'a@b.c' },
      request: {
        cookies: { s: '1' },
        data: 'secret',
        query_string: 'token=1',
        headers: { authorization: 'Bearer x', 'x-api-key': 'k', accept: '*/*' },
      },
    } as Sentry.ErrorEvent);
    expect(event.user).toBeUndefined();
    expect(event.request).toEqual({ headers: { accept: '*/*' } });
  });

  it('captures a synthetic error end to end with release, environment and no user', async () => {
    const envelopes: string[] = [];
    const started = initSentry(
      { dsn: 'https://k@o0.ingest.sentry.io/1', release: 'rel-1', environment: 'test' },
      {
        transport: () => ({
          send: async (envelope) => {
            envelopes.push(JSON.stringify(envelope));
            return {};
          },
          flush: async () => true,
        }),
      },
    );
    expect(started).toBe(true);

    Sentry.setUser({ id: 'private-user', email: 'private@example.test' });
    await captureSyntheticError('unit');

    const sent = envelopes.join('\n');
    expect(sent).toContain('synthetic-capture-check: unit');
    expect(sent).toContain('rel-1');
    expect(sent).toContain('test');
    expect(sent).not.toContain('"user"');
  });
});
