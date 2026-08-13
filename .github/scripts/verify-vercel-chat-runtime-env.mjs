#!/usr/bin/env node

import { existsSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const REQUIRED_VERCEL_CHAT_RUNTIME_VARS = Object.freeze([
  'DATABASE_URL',
  'OPENAI_API_KEY',
  'CRON_SECRET',
]);

const DEFAULT_ENV_FILE = '.vercel/.env.production.local';

export function parseEnvAssignments(contents) {
  const assignments = new Map();

  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }

    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      continue;
    }

    assignments.set(match[1], unquoteEnvValue(match[2]));
  }

  return assignments;
}

export function findMissingRequiredVariables(
  contents,
  required = REQUIRED_VERCEL_CHAT_RUNTIME_VARS,
) {
  const assignments = parseEnvAssignments(contents);
  return required.filter((name) => {
    const value = assignments.get(name);
    return value === undefined || value.trim() === '';
  });
}

export function verifyVercelChatRuntimeEnv({ envFile, contents } = {}) {
  const resolvedFile = envFile ?? DEFAULT_ENV_FILE;

  if (contents === undefined) {
    if (!existsSync(resolvedFile)) {
      return {
        ok: false,
        missingFile: true,
        envFile: resolvedFile,
        missingVariables: [...REQUIRED_VERCEL_CHAT_RUNTIME_VARS],
      };
    }

    contents = readFileSync(resolvedFile, 'utf8');
  }

  const missingVariables = findMissingRequiredVariables(contents);
  return {
    ok: missingVariables.length === 0,
    missingFile: false,
    envFile: resolvedFile,
    missingVariables,
  };
}

export function formatVerificationErrors(result) {
  if (result.missingFile) {
    return [`Missing Vercel production env file: ${result.envFile}`];
  }

  return result.missingVariables.map(
    (name) => `Missing required Vercel production variable: ${name}`,
  );
}

export function main(argv = process.argv.slice(2)) {
  const result = verifyVercelChatRuntimeEnv({ envFile: argv[0] ?? DEFAULT_ENV_FILE });
  const errors = formatVerificationErrors(result);

  for (const error of errors) {
    console.error(`::error::${error}`);
  }

  if (!result.ok) {
    process.exitCode = 1;
    return 1;
  }

  return 0;
}

function unquoteEnvValue(rawValue) {
  if (
    (rawValue.startsWith('"') && rawValue.endsWith('"') && rawValue.length >= 2) ||
    (rawValue.startsWith("'") && rawValue.endsWith("'") && rawValue.length >= 2)
  ) {
    return rawValue.slice(1, -1);
  }

  return rawValue;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
