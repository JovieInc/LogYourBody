import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  LAUNCH_CONTRACT,
  LAUNCH_CONTRACT_DIGEST,
} from './fixtures/lyb-certification/lyb-launch-contract.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

// These are requirements for the parent journey, not claims of implemented recovery.
const states = {
  ready: ['launch.timeline', 'launch.stats', 'launch.directive'],
  denial: ['launch.baseline', 'launch.recovery'],
  'no-data': ['launch.baseline', 'launch.timeline', 'launch.stats', 'launch.recovery'],
  offline: ['launch.recovery'],
  stale: ['launch.stats', 'launch.drift', 'launch.recovery'],
  conflicting: ['launch.drift', 'launch.recovery'],
  'unsafe-date': ['launch.deadline', 'launch.safety'],
  'impossible-date': ['launch.deadline', 'launch.safety'],
  'expired-date': ['launch.return'],
  maintenance: ['launch.deadline', 'launch.return'],
};

/** Read the canonical native registries; unsupported declaration syntax fails closed. */
function enumCases(source, name) {
  const uncommented = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  const body = uncommented.match(
    new RegExp(`enum\\s+${name}\\b[^\\{]*\\{([\\s\\S]*?)^\\}`, 'm'),
  )?.[1];
  if (!body) throw new Error(`Missing native registry: ${name}`);
  const cases = [];
  let depth = 0;
  for (const line of body.split('\n')) {
    const declaration = depth === 0 ? line.match(/^\s*case\s+(.+)$/) : null;
    if (declaration) {
      for (const entry of declaration[1].split(',')) {
        const value = entry.trim().match(/^(\w+)(?:\s*=\s*"([^"]+)")?$/);
        if (!value) throw new Error(`Unsupported native registry case: ${name}.${entry.trim()}`);
        cases.push(value[2] ?? value[1]);
      }
    }
    // Ignore switch cases in computed properties, but include enum cases declared
    // after properties. Braces in strings are not Swift declaration boundaries.
    const code = line.replace(/"(?:\\.|[^"\\])*"/g, '');
    depth += (code.match(/\{/g)?.length ?? 0) - (code.match(/\}/g)?.length ?? 0);
  }
  if (depth !== 0 || !cases.length || new Set(cases).size !== cases.length) {
    throw new Error(`Empty or duplicate native registry: ${name}`);
  }
  return cases;
}

export function nativeSurfaces(root = repositoryRoot) {
  const read = (path) => readFileSync(resolve(root, path), 'utf8');
  return [
    ...enumCases(read('apps/ios/LogYourBody/DesignSystem/Theme.swift'), 'WorldClassScreen').map(
      (id) => `ios.screen.${id}`,
    ),
    ...enumCases(
      read('apps/ios/LogYourBody/Views/MainTabViewPolicies.swift'),
      'PaidAppSurface',
    ).map((id) => `ios.mode.${id}`),
  ].sort();
}

/**
 * Contract paths plus every primary-route state. Coverage keys only — this does
 * not claim those paths were executed on an installed build.
 */
export function launchEvidencePathIds() {
  const contractIds = LAUNCH_CONTRACT.requiredPaths.map((path) => path.id);
  const routeStateIds = LAUNCH_CONTRACT.primarySurfaces.flatMap((surface) =>
    Object.keys(states).map((state) => `${surface}:${state}`),
  );
  return { contractIds, routeStateIds, all: [...contractIds, ...routeStateIds] };
}

/** Bind the parent's exact XCTest selectors without manufacturing execution evidence. */
export function emitLaunchManifest(bindings, root = repositoryRoot) {
  const observed = nativeSurfaces(root);
  const unknown = observed.filter((id) => !Object.hasOwn(LAUNCH_CONTRACT.surfaces, id));
  if (unknown.length) throw new Error(`Unclassified native surfaces: ${unknown.join(', ')}`);

  if (!bindings || typeof bindings !== 'object' || Array.isArray(bindings)) {
    throw new Error('Expected path ID → XCTest identifier array bindings');
  }
  const requiredIds = new Set(LAUNCH_CONTRACT.requiredPaths.map((path) => path.id));
  for (const id of Object.keys(bindings)) {
    if (!requiredIds.has(id)) throw new Error(`Unknown launch path binding: ${id}`);
  }
  const paths = LAUNCH_CONTRACT.requiredPaths.map((path) => {
    const testIds = bindings[path.id];
    if (
      !Array.isArray(testIds) ||
      !testIds.length ||
      testIds.some((id) => typeof id !== 'string' || !/^[\w.]+\/test\w+\(\)$/.test(id)) ||
      new Set(testIds).size !== testIds.length
    ) {
      throw new Error(`Missing or invalid XCTest bindings: ${path.id}`);
    }
    return { ...structuredClone(path), testIds: [...testIds] };
  });

  return {
    schema: 'lyb-native-certification/v2',
    sourceIssue: 'LYB-271',
    launchContract: {
      schema: LAUNCH_CONTRACT.schema,
      digest: LAUNCH_CONTRACT_DIGEST,
      primarySurfaces: [...LAUNCH_CONTRACT.primarySurfaces],
      surfaces: { ...LAUNCH_CONTRACT.surfaces },
    },
    paths,
    routes: LAUNCH_CONTRACT.primarySurfaces.map((surface) => ({
      surface,
      states: Object.entries(states).map(([id, pathIds]) => ({ id, pathIds: [...pathIds] })),
    })),
    observedNativeSurfaces: observed,
  };
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  try {
    const [bindingsPath, ...extra] = process.argv.slice(2);
    if (!bindingsPath || extra.length) {
      throw new Error('usage: node scripts/lyb-launch-manifest.mjs <xctest-bindings.json>');
    }
    const manifest = emitLaunchManifest(JSON.parse(readFileSync(bindingsPath, 'utf8')));
    process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
