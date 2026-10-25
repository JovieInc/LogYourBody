// Sentry's server entry does not export browser router hooks.
export { captureRouterTransitionStart } from '@sentry/nextjs';
export { initSentry } from './sentry';
