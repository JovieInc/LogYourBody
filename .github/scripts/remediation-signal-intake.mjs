#!/usr/bin/env node
/** File Symphony remediation issues unless REMEDIATION_INTAKE_DISABLED=1. Linear failures exit 0. */
import { readFileSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { missingLinearKeyWarning } from './lib/linear-issue-intake.mjs';
import { runRemediationIntake } from './remediation-signal.mjs';

function readText(path) {
  if (!path) return '';
  try {
    return readFileSync(path, 'utf8');
  } catch {
    return '';
  }
}

export function readGithubEvent(env = process.env) {
  const text = readText(env.GITHUB_EVENT_PATH);
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

async function main() {
  const env = process.env;
  const result = await runRemediationIntake({
    env,
    eventName: env.GITHUB_EVENT_NAME,
    event: readGithubEvent(env),
    previous: readText(env.REMEDIATION_PREVIOUS_FILE).trim(),
    httpStatus: env.REMEDIATION_HTTP_STATUS,
  });
  console.log(JSON.stringify(result));
  if (env.REMEDIATION_STATE_FILE) {
    rmSync(`${env.REMEDIATION_STATE_FILE}.dirty`, { force: true });
  }
  if (result.state && env.REMEDIATION_STATE_FILE) {
    mkdirSync(dirname(env.REMEDIATION_STATE_FILE), { recursive: true });
    writeFileSync(env.REMEDIATION_STATE_FILE, `${result.state}\n`);
    writeFileSync(`${env.REMEDIATION_STATE_FILE}.dirty`, '1\n');
  }
  if (!result.ok) {
    const reason = result.reason === 'missing_linear_api_key' ? missingLinearKeyWarning() : result.reason;
    console.warn(`::warning::Linear intake failed open (${reason}).`);
  }
}

const isDirectRun = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isDirectRun) {
  main().catch((error) => {
    console.warn(`::warning::Linear intake failed open (${error instanceof Error ? error.message : error}).`);
    process.exit(0);
  });
}
