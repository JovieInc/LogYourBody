import assert from 'node:assert/strict';

export const QUESTIONNAIRE = 'docs/compliance/app-store-privacy.json';
const POLICY = 'shared/legal/privacy-policy.md';
const INFO = 'apps/ios/LogYourBody/Info.plist';
const APP = 'apps/ios/LogYourBody/';
const REQUIRED_TYPES = [
  'Health',
  'Fitness',
  'Sensitive Info',
  'Name',
  'Email Address',
  'Photos or Videos',
  'User ID',
  'Device ID',
  'Purchase History',
  'Product Interaction',
  'Crash Data',
  'Performance Data',
  'Other Diagnostic Data',
  'Customer Support',
  'Other User Content',
  'Other Data Types',
];
const PURPOSES = new Set([
  'App Functionality',
  'Analytics',
  'Product Personalization',
  'Developer’s Advertising or Marketing',
  'Third-Party Advertising',
  'Other Purposes',
]);

function same(actual, expected, message) {
  assert.equal(JSON.stringify(actual), JSON.stringify(expected), message);
}

function sorted(values) {
  return [...values].sort();
}

function xmlText(value) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
  return value.replace(/&(amp|lt|gt|quot|apos);/g, (_, key) => entities[key]).trim();
}

function assertHealthDataDisclosure(source, definitions, descriptions, policy) {
  // LYB-189: require each native HealthKit type in the policy's Health Data bullet.
  const names = new Map([
    ['bodyMass', { name: 'weight', pattern: /\bweight\b/i }],
    [
      'bodyFatPercentage',
      {
        name: 'body fat percentage',
        pattern: /\bbody[ -]fat (?:percentage\b|%)/i,
        usage: /\bbody[ -](?:fat|composition)\b/i,
      },
    ],
    ['height', { name: 'height', pattern: /\bheight\b/i }],
    ['stepCount', { name: 'step count', pattern: /\b(?:step count|steps)\b/i }],
    ['dateOfBirth', { name: 'date of birth', pattern: /\bdate of birth\b/i }],
    ['biologicalSex', { name: 'biological sex', pattern: /\bbiological sex\b/i }],
    ['heartRate', { name: 'heart rate', pattern: /\bheart rate\b/i }],
  ]);
  const directCharacteristics = {
    dateOfBirthComponents: 'dateOfBirth',
    dateOfBirth: 'dateOfBirth',
    biologicalSex: 'biologicalSex',
    bloodType: 'bloodType',
    fitzpatrickSkinType: 'fitzpatrickSkinType',
    wheelchairUse: 'wheelchairUse',
    activityMoveMode: 'activityMoveMode',
  };
  const identifiers = new Set(definitions.map(({ identifier }) => identifier));
  for (const [, identifier] of source.matchAll(
    /\bHK(?:Quantity|Characteristic|Category)TypeIdentifier\s*\.\s*(\w+)/g,
  ))
    identifiers.add(identifier);
  // Characteristic getters can read existing permissions without a type declaration.
  for (const [, method] of source.matchAll(
    /\.(dateOfBirthComponents|dateOfBirth|biologicalSex|bloodType|fitzpatrickSkinType|wheelchairUse|activityMoveMode)\s*\(/g,
  ))
    identifiers.add(directCharacteristics[method]);
  const usage = descriptions
    .filter(([key]) => /^NSHealth(?:Share|Update)UsageDescription$/.test(key))
    .map(([, text]) => text)
    .join('\n');
  for (const [identifier, { pattern, usage: alias = pattern }] of names) {
    if (alias.test(usage)) identifiers.add(identifier);
  }
  const bullets = policy.match(/^- \*\*Health Data\*\*:[^\n]*(?:\n[ \t]+\S[^\n]*)*/gm) ?? [];
  assert.equal(bullets.length, 1, 'Expected one Health Data disclosure bullet');
  for (const identifier of identifiers) {
    const entry = names.get(identifier);
    assert.ok(entry, `Health Data disclosure mapping missing: ${identifier}`);
    assert.match(bullets[0], entry.pattern, `Health Data disclosure missing: ${entry.name}`);
  }
}

// LYB-194: reject HealthKit authorization and usage-description drift from ASC answers.
// Only the supplied snapshot is read, including when the ratchet checks the Git base.
export function scan({ files, readSource }) {
  try {
    const read = (path) => {
      assert.ok(files.includes(path), `Missing privacy source: ${path}`);
      return readSource(path);
    };
    const answers = JSON.parse(read(QUESTIONNAIRE));
    assert.equal(
      answers.schema,
      'lyb.app-store-privacy/v1',
      'Invalid privacy questionnaire schema',
    );
    assert.ok(
      Number.isInteger(answers.version) && answers.version > 0,
      'Missing questionnaire version',
    );
    assert.match(answers.reviewedAt, /^\d{4}-\d{2}-\d{2}$/, 'Missing review date');
    assert.match(
      answers.reviewedNativeSourceCommit,
      /^[a-f0-9]{40}$/,
      'Missing native source revision',
    );
    assert.ok(
      ['pending', 'confirmed'].includes(answers.ascComparison?.status),
      'Missing ASC comparison status',
    );
    assert.ok(
      answers.ascComparison.status === 'pending' ||
        (typeof answers.ascComparison.evidence === 'string' &&
          answers.ascComparison.evidence.trim()),
      'Confirmed ASC comparison requires a release evidence reference',
    );
    assert.equal(answers.dataCollected, true, 'Collected data must be declared');
    const rows = answers.dataTypes;
    assert.ok(Array.isArray(rows), 'Missing ASC data types');
    same(
      sorted(rows.map((row) => row.type)),
      sorted(REQUIRED_TYPES),
      'ASC data type inventory changed',
    );
    for (const row of rows) {
      assert.ok(row.data?.trim(), `Missing data description: ${row.type}`);
      assert.ok(
        Array.isArray(row.purposes) &&
          row.purposes.length > 0 &&
          row.purposes.every((purpose) => PURPOSES.has(purpose)),
        `Invalid ASC purposes: ${row.type}`,
      );
      assert.equal(typeof row.linkedToUser, 'boolean', `Missing linkage answer: ${row.type}`);
      assert.equal(typeof row.tracking, 'boolean', `Missing tracking answer: ${row.type}`);
      assert.ok(
        Array.isArray(row.thirdPartyUse) &&
          row.thirdPartyUse.length > 0 &&
          row.thirdPartyUse.every((use) => typeof use === 'string' && use.trim()),
        `Missing third-party use: ${row.type}`,
      );
      assert.ok(
        Array.isArray(row.sources) && row.sources.length > 0,
        `Missing evidence: ${row.type}`,
      );
      row.sources.forEach(read);
    }
    assert.equal(
      answers.dataUsedForTracking,
      rows.some((row) => row.tracking),
      'Overall tracking answer differs from data-type answers',
    );

    const managers = files.filter((path) =>
      /^apps\/ios\/LogYourBody\/Services\/HealthKitManager(?:\+[^/]+)?\.swift$/.test(path),
    );
    assert.ok(managers.length > 0, 'Missing HealthKitManager source');
    // This deliberately supports only the reviewed literal type/authorization form.
    // A refactor to computed sets or another constructor must update this guard.
    const source = managers
      .map(read)
      .join('\n')
      .replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, '');
    const definitions = [
      ...source.matchAll(
        /var\s+(\w+)\s*:\s*HK(Quantity|Characteristic)Type\s*\{\s*return\s+HK\2Type\.(?:quantityType|characteristicType)\(forIdentifier:\s*\.(\w+)\)!\s*\}/g,
      ),
    ].map(([, variable, kind, identifier]) => ({ variable, kind, identifier }));
    same(
      definitions.length,
      [
        ...source.matchAll(
          /\b(?:quantityType|characteristicType|categoryType)\s*\(\s*forIdentifier\s*:/g,
        ),
      ].length,
      'Unreviewed HealthKit type constructor',
    );
    const expected = answers.healthKit;
    assert.ok(Array.isArray(expected) && expected.length > 0, 'Missing HealthKit inventory');
    const normalize = (types) =>
      types.map(({ variable, kind, identifier }) => `${variable}:${kind}:${identifier}`).sort();
    same(
      normalize(definitions),
      normalize(expected),
      'HealthKit type definitions differ from questionnaire',
    );
    for (const type of expected) {
      assert.ok(
        rows.some((row) => row.type === type.dataType),
        `Unmapped HealthKit type: ${type.identifier}`,
      );
      assert.equal(typeof type.read, 'boolean', 'Missing HealthKit read answer');
      assert.equal(typeof type.write, 'boolean', 'Missing HealthKit write answer');
    }
    for (const [name, flag] of [
      ['typesToRead', 'read'],
      ['typesToWrite', 'write'],
    ]) {
      const matches = [
        ...source.matchAll(
          new RegExp(
            `let\\s+${name}\\s*:\\s*Set<HK(?:Object|Quantity)Type>\\s*=\\s*\\[([^\\]]*)\\]`,
            'g',
          ),
        ),
      ];
      assert.equal(matches.length, 1, `Unreviewed HealthKit ${name} declaration`);
      const variables = matches[0][1]
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
      same(
        sorted(variables),
        sorted(expected.filter((type) => type[flag]).map((type) => type.variable)),
        `HealthKit ${flag} authorization differs from questionnaire`,
      );
    }
    same(
      [...source.matchAll(/\.requestAuthorization\s*\(/g)].length,
      1,
      'Unreviewed HealthKit authorization call',
    );
    assert.match(
      source,
      /\.requestAuthorization\(toShare:\s*typesToWrite,\s*read:\s*typesToRead\)/,
      'HealthKit authorization no longer uses reviewed sets',
    );
    // A second HealthKit permission owner must be reviewed rather than escaping the manager scan.
    for (const path of files.filter(
      (path) => path.startsWith(APP) && path.endsWith('.swift') && !managers.includes(path),
    )) {
      assert.doesNotMatch(
        read(path),
        /\.requestAuthorization\s*\(\s*toShare:/,
        `Unreviewed HealthKit authorization owner: ${path}`,
      );
    }

    const plist = read(INFO);
    const descriptions = [
      ...plist.matchAll(/<key>(NS\w+UsageDescription)<\/key>\s*<string>([\s\S]*?)<\/string>/g),
    ]
      .map(([, key, value]) => [key, xmlText(value)])
      .sort();
    const usageKeys = [...plist.matchAll(/<key>(NS\w+UsageDescription)<\/key>/g)].map(
      ([, key]) => key,
    );
    same(descriptions.length, usageKeys.length, 'Usage description is not a literal string');
    same(
      descriptions,
      Object.entries(answers.usageDescriptions)
        .map(([key, entry]) => [key, entry.text])
        .sort(),
      'Info.plist usage descriptions differ from questionnaire',
    );
    for (const [key, entry] of Object.entries(answers.usageDescriptions)) {
      assert.ok(
        entry.dataTypes.length > 0 &&
          entry.dataTypes.every(
            (type) => type === 'On-device only' || rows.some((row) => row.type === type),
          ),
        `Unmapped permission: ${key}`,
      );
    }
    assertHealthDataDisclosure(source, definitions, descriptions, read(POLICY));
    return [];
  } catch (error) {
    return [{ path: QUESTIONNAIRE, key: error.message.split('\n')[0] }];
  }
}
