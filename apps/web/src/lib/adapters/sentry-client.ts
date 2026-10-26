// This SDK export only exists in the browser build, so keep it out of the
// shared adapter loaded by server and edge instrumentation.
export { captureRouterTransitionStart } from '@sentry/nextjs';
export { initSentry } from './sentry';
