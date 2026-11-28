#!/usr/bin/env node
import console from 'node:console';
import process from 'node:process';
import { setTimeout } from 'node:timers/promises';
import { pathToFileURL, URL } from 'node:url';

const PENDING_STATES = new Set(['INITIALIZING', 'QUEUED', 'BUILDING']);

export async function run({
  env = process.env,
  fetchImpl = globalThis.fetch,
  sleep = setTimeout,
  now = Date.now,
  log = console,
  timeoutMs = 180_000,
  pollIntervalMs = 5_000,
} = {}) {
  const { DEPLOYMENT_URL, VERCEL_TOKEN, VERCEL_ORG_ID } = env;
  if (!DEPLOYMENT_URL || !VERCEL_TOKEN || !VERCEL_ORG_ID) {
    log.error(
      '::error::DEPLOYMENT_URL, VERCEL_TOKEN and VERCEL_ORG_ID are required to verify Vercel readiness.',
    );
    return 1;
  }

  let deployment;
  try {
    deployment = new URL(DEPLOYMENT_URL);
    if (
      deployment.protocol !== 'https:' ||
      deployment.username ||
      deployment.password ||
      deployment.pathname !== '/' ||
      deployment.search ||
      deployment.hash
    )
      throw new Error();
  } catch {
    log.error('::error::Vercel deploy did not return a valid HTTPS deployment origin.');
    return 1;
  }

  const api = new URL(
    `https://api.vercel.com/v13/deployments/${encodeURIComponent(deployment.host)}`,
  );
  api.searchParams.set('teamId', VERCEL_ORG_ID);
  const deadline = now() + timeoutMs;
  while (now() < deadline) {
    let state;
    try {
      const response = await fetchImpl(api, {
        headers: { Authorization: `Bearer ${VERCEL_TOKEN}` },
        signal: globalThis.AbortSignal.timeout(Math.min(10_000, deadline - now())),
        redirect: 'error',
      });
      if (!response.ok) {
        log.error(
          `::error::Vercel deployment inspection failed (HTTP ${response.status}); readiness is unverified.`,
        );
        return 1;
      }
      state = (await response.json()).readyState;
    } catch {
      // Never print API bodies or exception text, which can contain credentials.
      log.error(
        '::error::Vercel deployment inspection failed (network, timeout or invalid JSON); readiness is unverified.',
      );
      return 1;
    }

    if (state === 'READY') {
      log.log(`Vercel deployment is READY: ${deployment.origin}`);
      return 0;
    }
    if (state === 'BLOCKED') {
      log.error(
        `::error::Vercel production deployment is BLOCKED: ${deployment.origin}. Tim must inspect https://vercel.com/jovie/log-your-body for a project/team restriction (settings, usage or billing). CI cannot release this hold.`,
      );
      return 1;
    }
    if (state === 'ERROR' || state === 'CANCELED') {
      log.error(
        `::error::Vercel production deployment is ${state}: ${deployment.origin}. Inspect the deployment in the Vercel dashboard.`,
      );
      return 1;
    }
    if (!PENDING_STATES.has(state)) {
      log.error(
        '::error::Vercel deployment returned a missing or unknown readyState; readiness is unverified.',
      );
      return 1;
    }
    log.log(`Vercel deployment is ${state}; waiting for READY.`);
    const remaining = deadline - now();
    if (remaining > 0) await sleep(Math.min(pollIntervalMs, remaining));
  }
  log.error(
    `::error::Vercel deployment did not reach READY within ${timeoutMs / 1000}s: ${deployment.origin}. Inspect the deployment in the Vercel dashboard.`,
  );
  return 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await run();
}
