import { captureRouterTransitionStart, initSentry } from "@/lib/adapters/sentry";

initSentry();

export const onRouterTransitionStart = captureRouterTransitionStart;
