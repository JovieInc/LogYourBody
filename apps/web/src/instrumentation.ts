import { captureRequestError, initSentry } from '@/lib/adapters/sentry';

export function register() {
  initSentry();
}

export const onRequestError = captureRequestError;
