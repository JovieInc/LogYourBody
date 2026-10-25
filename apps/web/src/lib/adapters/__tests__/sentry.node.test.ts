import * as Sentry from "@sentry/nextjs";
import {
  captureSyntheticError,
  initSentry,
  redactSentryEvent,
  sentryRuntimeConfig,
} from "../sentry";

describe("sentry adapter", () => {
  afterEach(async () => {
    await Sentry.close();
  });

  it("stays off without a DSN", () => {
    expect(initSentry({})).toBe(false);
    expect(sentryRuntimeConfig({}).dsn).toBeUndefined();
  });

  it("reads release and environment from config", () => {
    expect(
      sentryRuntimeConfig({
        NEXT_PUBLIC_SENTRY_DSN: "https://k@o0.ingest.sentry.io/1",
        NEXT_PUBLIC_SENTRY_RELEASE: "abc123",
        VERCEL_ENV: "production",
      })
    ).toEqual({
      dsn: "https://k@o0.ingest.sentry.io/1",
      release: "abc123",
      environment: "production",
    });
  });

  it("strips user, cookies, bodies and credential headers", () => {
    const event = redactSentryEvent({
      type: undefined,
      user: { id: "u", email: "a@b.c" },
      request: {
        cookies: { s: "1" },
        data: "secret",
        query_string: "token=1",
        headers: { authorization: "Bearer x", "x-api-key": "k", accept: "*/*" },
      },
    } as Sentry.ErrorEvent);
    expect(event.user).toBeUndefined();
    expect(event.request).toEqual({ headers: { accept: "*/*" } });
  });

  it("captures a synthetic error end to end with release, environment and no user", async () => {
    const envelopes: string[] = [];
    const started = initSentry(
      { dsn: "https://k@o0.ingest.sentry.io/1", release: "rel-1", environment: "test" },
      {
        transport: () => ({
          send: async (envelope) => {
            envelopes.push(JSON.stringify(envelope));
            return {};
          },
          flush: async () => true,
        }),
      }
    );
    expect(started).toBe(true);

    await captureSyntheticError("unit");

    const sent = envelopes.join("\n");
    expect(sent).toContain("synthetic-capture-check: unit");
    expect(sent).toContain("rel-1");
    expect(sent).not.toContain("\"user\"");
  });
});
