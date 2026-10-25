/**
 * Sentry vendor adapter for the LogYourBody web app. The only module that
 * imports the SDK (see scripts/check-vendor-boundaries.js); instrumentation
 * files call these helpers.
 *
 * Privacy: sendDefaultPii is off; events are stripped of user, cookies, auth
 * headers, query strings and request bodies before they leave the process.
 * Config (names only): NEXT_PUBLIC_SENTRY_DSN, NEXT_PUBLIC_SENTRY_RELEASE,
 * NEXT_PUBLIC_SENTRY_ENVIRONMENT, SENTRY_AUTH_TOKEN/SENTRY_ORG/SENTRY_PROJECT
 * (build-time sourcemap upload only).
 */
import * as Sentry from '@sentry/nextjs';

const SENSITIVE_HEADERS = /^(authorization|cookie|set-cookie|x-.*(token|key|secret).*)$/i;

type SentryEvent = Sentry.ErrorEvent;

export function redactSentryEvent<T extends SentryEvent>(event: T): T {
  delete event.user;
  if (event.request) {
    delete event.request.cookies;
    delete event.request.data;
    delete event.request.query_string;
    if (event.request.headers) {
      for (const key of Object.keys(event.request.headers)) {
        if (SENSITIVE_HEADERS.test(key)) delete event.request.headers[key];
      }
    }
  }
  return event;
}

export interface SentryRuntimeConfig {
  dsn?: string;
  release?: string;
  environment?: string;
}

export function sentryRuntimeConfig(
  env: Record<string, string | undefined> = process.env
): SentryRuntimeConfig {
  return {
    dsn: env.NEXT_PUBLIC_SENTRY_DSN || undefined,
    release: env.NEXT_PUBLIC_SENTRY_RELEASE || undefined,
    environment:
      env.NEXT_PUBLIC_SENTRY_ENVIRONMENT || env.VERCEL_ENV || env.NODE_ENV,
  };
}

export function initSentry(
  config: SentryRuntimeConfig = sentryRuntimeConfig(),
  overrides: Partial<Sentry.NodeOptions> = {}
): boolean {
  if (!config.dsn) return false;
  Sentry.init({
    dsn: config.dsn,
    release: config.release,
    environment: config.environment,
    sendDefaultPii: false,
    tracesSampleRate: 0,
    beforeSend: redactSentryEvent,
    ...overrides,
  });
  return true;
}

export const captureRequestError = Sentry.captureRequestError;
export const captureRouterTransitionStart = Sentry.captureRouterTransitionStart;

/** Synthetic error used to prove end-to-end capture per release. */
export async function captureSyntheticError(label: string): Promise<string> {
  const id = Sentry.captureException(new Error(`synthetic-capture-check: ${label}`), {
    tags: { synthetic: "true" },
  });
  await Sentry.flush(5000);
  return id;
}
