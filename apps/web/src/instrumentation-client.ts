import { captureRouterTransitionStart, initSentry } from '@/lib/adapters/sentry-client';

initSentry();

export const onRouterTransitionStart = captureRouterTransitionStart;
