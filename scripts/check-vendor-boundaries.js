#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');

const ignoredDirectories = new Set([
  '.git',
  '.next',
  '.turbo',
  '.vercel',
  'build',
  'coverage',
  'DerivedData',
  'dist',
  'node_modules',
]);

const swiftRoots = ['apps/ios/LogYourBody'];
const typescriptRoots = ['apps/web/src', 'packages'];

const swiftVendorModules = [
  { name: 'Clerk', modules: ['Clerk'] },
  { name: 'OpenAI', modules: ['OpenAI'] },
  { name: 'PostHog', modules: ['PostHog', 'PostHogSwift'] },
  { name: 'RevenueCat', modules: ['RevenueCat', 'RevenueCatUI'] },
  { name: 'Sentry', modules: ['Sentry'] },
  { name: 'Statsig', modules: ['Statsig'] },
  { name: 'Supabase', modules: ['Supabase'] },
];

const typescriptVendorModules = [
  { name: 'Clerk', prefixes: ['@clerk/'] },
  { name: 'OpenAI', modules: ['openai'] },
  { name: 'PostHog', modules: ['posthog-js', 'posthog-node', 'posthog'] },
  { name: 'RevenueCat', modules: ['revenuecat', 'react-native-purchases'] },
  { name: 'Sentry', prefixes: ['@sentry/'] },
  { name: 'Statsig', prefixes: ['@statsig/'] },
  { name: 'Supabase', prefixes: ['@supabase/'] },
];

const swiftAllowedBoundaries = [
  {
    label: 'apps/ios/LogYourBody/Services/**',
    test: (relativePath) => relativePath.startsWith('apps/ios/LogYourBody/Services/'),
  },
];

const typescriptAllowedBoundaries = [
  {
    label: 'apps/web/src/lib/ports/**',
    test: (relativePath) => relativePath.startsWith('apps/web/src/lib/ports/'),
  },
  {
    label: 'apps/web/src/lib/supabase/**',
    test: (relativePath) => relativePath.startsWith('apps/web/src/lib/supabase/'),
  },
  {
    label: 'apps/web/src/lib/statsigAnalyticsAdapter.ts',
    test: (relativePath) => relativePath === 'apps/web/src/lib/statsigAnalyticsAdapter.ts',
  },
  {
    label: 'apps/web/src/lib/sync/realtime-sync-manager.ts',
    test: (relativePath) => relativePath === 'apps/web/src/lib/sync/realtime-sync-manager.ts',
  },
  {
    label: 'apps/web/src/middleware.ts',
    test: (relativePath) => relativePath === 'apps/web/src/middleware.ts',
  },
  {
    label: 'packages/**/{adapters,ports,services}/**',
    test: (relativePath) =>
      /^packages\/[^/]+\/(?:src\/)?(?:adapters|ports|services)\//.test(relativePath),
  },
];

function toRelative(filepath) {
  return path.relative(repoRoot, filepath).split(path.sep).join('/');
}

function isDirectoryIgnored(dirname) {
  return ignoredDirectories.has(dirname);
}

function walkFiles(rootRelativePath, extensions) {
  const root = path.join(repoRoot, rootRelativePath);
  if (!fs.existsSync(root)) {
    return [];
  }

  const files = [];
  const stack = [root];

  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });

    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!isDirectoryIgnored(entry.name)) {
          stack.push(path.join(current, entry.name));
        }
        continue;
      }

      if (entry.isFile() && extensions.has(path.extname(entry.name))) {
        files.push(path.join(current, entry.name));
      }
    }
  }

  return files.sort();
}

function isTestFile(relativePath) {
  return (
    /(^|\/)(__mocks__|__tests__|cypress|e2e|tests?)\//.test(relativePath) ||
    /\.(cy|spec|test)\.[cm]?[jt]sx?$/.test(relativePath)
  );
}

function buildLineStarts(content) {
  const starts = [0];
  for (let index = 0; index < content.length; index += 1) {
    if (content[index] === '\n') {
      starts.push(index + 1);
    }
  }
  return starts;
}

function lineForIndex(lineStarts, index) {
  let low = 0;
  let high = lineStarts.length - 1;

  while (low <= high) {
    const middle = Math.floor((low + high) / 2);
    if (lineStarts[middle] <= index) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }

  return high + 1;
}

function matchSwiftVendor(moduleName) {
  return swiftVendorModules.find((vendor) => vendor.modules.includes(moduleName));
}

function matchTypescriptVendor(moduleName) {
  return typescriptVendorModules.find((vendor) => {
    const exactMatch = vendor.modules?.some(
      (module) => moduleName === module || moduleName.startsWith(`${module}/`),
    );
    const prefixMatch = vendor.prefixes?.some((prefix) => moduleName.startsWith(prefix));
    return exactMatch || prefixMatch;
  });
}

function isAllowed(relativePath, boundaries) {
  return boundaries.some((boundary) => boundary.test(relativePath));
}

function scanSwiftFile(filepath) {
  const content = fs.readFileSync(filepath, 'utf8');
  const lineStarts = buildLineStarts(content);
  const relativePath = toRelative(filepath);
  const violations = [];
  const importRegex =
    /(?:^|\n)\s*(?:@[\w()]+\s+)*import\s+(?:(?:class|struct|enum|protocol|func|var|let)\s+)?([A-Za-z_][A-Za-z0-9_]*)\b/g;

  for (const match of content.matchAll(importRegex)) {
    const moduleName = match[1];
    const vendor = matchSwiftVendor(moduleName);

    if (vendor && !isAllowed(relativePath, swiftAllowedBoundaries)) {
      violations.push({
        file: relativePath,
        line: lineForIndex(lineStarts, match.index),
        importTarget: moduleName,
        language: 'Swift',
        vendor: vendor.name,
      });
    }
  }

  return violations;
}

function collectTypescriptImports(content) {
  const imports = [];
  const patterns = [
    /(?:^|\n)\s*import\s+(?:type\s+)?(?:[\s\S]*?\s+from\s+)?['"]([^'"]+)['"]/g,
    /(?:^|\n)\s*export\s+(?:type\s+)?[\s\S]*?\s+from\s+['"]([^'"]+)['"]/g,
    /\brequire\(\s*['"]([^'"]+)['"]\s*\)/g,
    /\bimport\(\s*['"]([^'"]+)['"]\s*\)/g,
  ];

  for (const pattern of patterns) {
    for (const match of content.matchAll(pattern)) {
      imports.push({ moduleName: match[1], index: match.index });
    }
  }

  return imports;
}

function scanTypescriptFile(filepath) {
  const content = fs.readFileSync(filepath, 'utf8');
  const lineStarts = buildLineStarts(content);
  const relativePath = toRelative(filepath);
  const violations = [];

  for (const importStatement of collectTypescriptImports(content)) {
    const vendor = matchTypescriptVendor(importStatement.moduleName);

    if (vendor && !isAllowed(relativePath, typescriptAllowedBoundaries)) {
      violations.push({
        file: relativePath,
        line: lineForIndex(lineStarts, importStatement.index),
        importTarget: importStatement.moduleName,
        language: 'TypeScript/JavaScript',
        vendor: vendor.name,
      });
    }
  }

  return violations;
}

function printAllowedBoundaries() {
  console.error('\nAllowed iOS vendor boundaries:');
  for (const boundary of swiftAllowedBoundaries) {
    console.error(`  - ${boundary.label}`);
  }

  console.error('\nAllowed web/package vendor boundaries:');
  for (const boundary of typescriptAllowedBoundaries) {
    console.error(`  - ${boundary.label}`);
  }
}

function main() {
  const swiftFiles = swiftRoots.flatMap((root) => walkFiles(root, new Set(['.swift'])));
  const typescriptFiles = typescriptRoots
    .flatMap((root) => walkFiles(root, new Set(['.js', '.jsx', '.ts', '.tsx', '.cjs', '.mjs'])))
    .filter((filepath) => !isTestFile(toRelative(filepath)));

  const violations = [
    ...swiftFiles.flatMap(scanSwiftFile),
    ...typescriptFiles.flatMap(scanTypescriptFile),
  ].sort((a, b) => `${a.file}:${a.line}`.localeCompare(`${b.file}:${b.line}`));

  console.log('Vendor boundary check');
  console.log(`  Swift files scanned: ${swiftFiles.length}`);
  console.log(`  TypeScript/JavaScript files scanned: ${typescriptFiles.length}`);

  if (violations.length === 0) {
    console.log('\nNo direct vendor SDK imports outside approved boundaries.');
    return;
  }

  console.error(
    '\nVendor boundary violations found. Product, domain, and UI code must access third-party SDKs through internal services, ports, or adapters.',
  );

  for (const violation of violations) {
    console.error(
      `  - ${violation.file}:${violation.line} imports ${violation.importTarget} (${violation.vendor}, ${violation.language})`,
    );
  }

  printAllowedBoundaries();
  console.error('\nMove the vendor call behind an approved boundary or add a narrowly scoped boundary entry.');
  process.exit(1);
}

main();
