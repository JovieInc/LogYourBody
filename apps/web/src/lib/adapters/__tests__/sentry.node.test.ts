/** @jest-environment node */
import * as Sentry from '@sentry/nextjs';
import {
  captureSyntheticError,
  initSentry,
  isThirdPartyExtensionError,
  prepareSentryEvent,
  redactSentryEvent,
  sentryRuntimeConfig,
} from '../sentry';

/** LOG-YOUR-BODY-WEB-2: extension rejection on `/`, with no application frame. */
function extensionToLowerCaseEvent(): Sentry.ErrorEvent {
  return {
    type: undefined,
    exception: {
      values: [
        {
          type: 'TypeError',
          value: "Cannot read properties of undefined (reading 'toLowerCase')",
          mechanism: {
            type: 'auto.browser.global_handlers.onunhandledrejection',
            handled: false,
          },
          stacktrace: {
            frames: [
              { filename: 'ext:core/01_core.js', abs_path: 'ext:core/01_core.js', in_app: true },
              { filename: '<script>', abs_path: '<script>', in_app: true },
              {
                filename: '<obscura:bootstrap>',
                abs_path: '<obscura:bootstrap>',
                in_app: true,
              },
              { filename: '<script>', abs_path: '<script>', function: 'sN', in_app: true },
            ],
          },
        },
      ],
    },
  };
}

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

  it('drops the homepage extension toLowerCase rejection', () => {
    const event = extensionToLowerCaseEvent();
    expect(isThirdPartyExtensionError(event)).toBe(true);
    expect(prepareSentryEvent(event)).toBeNull();
  });

  it('drops a chrome-extension stack that has no application frame', () => {
    const event = extensionToLowerCaseEvent();
    event.exception!.values![0].stacktrace = {
      frames: [
        { filename: 'chrome-extension://abc/content.js', in_app: true },
        { filename: '<script>', in_app: true },
      ],
    };
    expect(prepareSentryEvent(event)).toBeNull();
  });

  it('keeps the same toLowerCase error when an application frame is present', () => {
    const event = extensionToLowerCaseEvent();
    event.exception?.values?.[0].stacktrace?.frames?.push({
      filename: 'https://www.logyourbody.com/_next/static/chunks/app/page.js',
      abs_path: 'https://www.logyourbody.com/_next/static/chunks/app/page.js',
      in_app: true,
    });
    expect(isThirdPartyExtensionError(event)).toBe(false);
    expect(prepareSentryEvent(event)?.exception?.values?.[0].value).toContain('toLowerCase');
  });

  it('keeps an inline script error that has no extension runtime frame', () => {
    const event = extensionToLowerCaseEvent();
    event.exception!.values![0].stacktrace = {
      frames: [{ filename: '<script>', abs_path: '<script>', function: 'sN', in_app: true }],
    };
    expect(prepareSentryEvent(event)?.exception?.values?.[0].type).toBe('TypeError');
  });

  it('keeps an error that has no stack to classify', () => {
    const event = extensionToLowerCaseEvent();
    delete event.exception?.values?.[0].stacktrace;
    expect(prepareSentryEvent(event)?.exception?.values?.[0].value).toContain('toLowerCase');
  });

  it('installs the extension filter on the Sentry client', () => {
    initSentry({ dsn: 'https://k@o0.ingest.sentry.io/1' });
    const beforeSend = Sentry.getClient()?.getOptions().beforeSend;
    expect(beforeSend?.(extensionToLowerCaseEvent(), {})).toBeNull();
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
