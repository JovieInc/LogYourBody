#!/usr/bin/env node
// Fails when any NEXT_PUBLIC_* variable in the Vercel project is marked Sensitive.
// `vercel pull` writes the literal "[SENSITIVE]" for sensitive variables and
// NEXT_PUBLIC_* values are inlined into browser code, so a sensitive one breaks
// the production deploy (and ships a placeholder). Names only are ever printed.
import { pathToFileURL } from 'node:url';

export function findSensitivePublicVars(envs) {
  const bad = new Map();
  for (const entry of envs ?? []) {
    if (typeof entry?.key !== 'string' || !entry.key.startsWith('NEXT_PUBLIC_')) continue;
    if (entry.type !== 'sensitive') continue;
    const targets = bad.get(entry.key) ?? new Set();
    for (const target of entry.target ?? []) targets.add(target);
    bad.set(entry.key, targets);
  }
  return [...bad.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, targets]) => `${key} is marked Sensitive in Vercel (${[...targets].sort().join(', ') || 'no target'}). NEXT_PUBLIC_* values are public by design; re-create it as a plain (non-sensitive) variable.`);
}

export async function run({ env = process.env, fetchImpl = fetch, log = console } = {}) {
  const { VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID } = env;
  if (!VERCEL_TOKEN || !VERCEL_ORG_ID || !VERCEL_PROJECT_ID) {
    log.error('::error::VERCEL_TOKEN, VERCEL_ORG_ID and VERCEL_PROJECT_ID are required to inspect Vercel env types.');
    return 1;
  }
  const url = `https://api.vercel.com/v9/projects/${VERCEL_PROJECT_ID}/env?teamId=${VERCEL_ORG_ID}`;
  const response = await fetchImpl(url, { headers: { Authorization: `Bearer ${VERCEL_TOKEN}` } });
  if (!response.ok) {
    log.error(`::error::Vercel env listing failed (${response.status}); refusing to pass without inspecting types.`);
    return 1;
  }
  const failures = findSensitivePublicVars((await response.json()).envs);
  for (const failure of failures) log.error(`::error::${failure}`);
  if (failures.length === 0) log.log('No NEXT_PUBLIC_* Vercel variable is marked Sensitive.');
  return failures.length === 0 ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await run();
}
