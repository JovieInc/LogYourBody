import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import test from 'node:test';
import { QUESTIONNAIRE, scan } from './app-privacy.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const files = execFileSync(
  'git',
  ['ls-files', '--cached', '--others', '--exclude-standard', '--deduplicate', '-z'],
  { cwd: root, encoding: 'utf8' },
)
  .split('\0')
  .filter((path) => path && existsSync(join(root, path)));
const info = 'apps/ios/LogYourBody/Info.plist';
const policy = 'shared/legal/privacy-policy.md';
const snapshot = new Map(
  files.map((path) => [
    path,
    /\.swift$/.test(path) || path === info || path === QUESTIONNAIRE || path === policy
      ? readFileSync(join(root, path), 'utf8')
      : '',
  ]),
);
const manager = 'apps/ios/LogYourBody/Services/HealthKitManager+Part01.swift';

function findings(edit = () => {}) {
  const copy = new Map(snapshot);
  edit(copy);
  return scan({ files: [...copy.keys()], readSource: (path) => copy.get(path) });
}

test('checked-in privacy answers match HealthKit and Info.plist', () => {
  assert.deepEqual(findings(), []);
});

test('the original missing-questionnaire gap fails closed', () => {
  assert.match(findings((copy) => copy.delete(QUESTIONNAIRE))[0].key, /Missing privacy source/);
});

test('LYB-189: the original steps-only Health Data disclosure fails', () => {
  const result = findings((copy) =>
    copy.set(
      policy,
      copy
        .get(policy)
        .replace(
          /^- \*\*Health Data\*\*:.*$/m,
          '- **Health Data**: Step count, activity data (when you grant permission to access Apple Health or similar services)',
        ),
    ),
  );
  assert.match(result[0]?.key ?? '', /Health Data disclosure missing: weight/);
});

test('each HealthKit read path must be named in the Health Data bullet itself', () => {
  for (const name of [
    'weight',
    'body fat percentage',
    'height',
    'step count',
    'date of birth',
    'biological sex',
  ]) {
    const result = findings((copy) => {
      const updated = copy
        .get(policy)
        .replace(/^- \*\*Health Data\*\*:.*$/m, (bullet) =>
          bullet.replace(new RegExp(name, 'i'), 'undisclosed metric'),
        );
      assert.notEqual(updated, copy.get(policy), `fixture must remove ${name}`);
      // Mentions outside this bullet cannot hide the collection gap.
      copy.set(policy, `${updated}\n## Other information\n${name}\n`);
    });
    assert.match(result[0]?.key ?? '', new RegExp(`Health Data disclosure missing: ${name}`));
  }
  assert.ok(findings((copy) => copy.delete(policy)).length);
  assert.ok(findings((copy) => copy.set(policy, '# Privacy Policy')).length);
});

test('a permission-string type needs Health Data disclosure even when ASC text is updated', () => {
  for (const key of ['NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription']) {
    const result = findings((copy) => {
      const answers = JSON.parse(copy.get(QUESTIONNAIRE));
      const entry = answers.usageDescriptions[key];
      const updated = `${entry.text} Heart rate.`;
      copy.set(info, copy.get(info).replace(entry.text, updated));
      entry.text = updated;
      copy.set(QUESTIONNAIRE, JSON.stringify(answers));
    });
    assert.match(result[0]?.key ?? '', /Health Data disclosure missing: heart rate/);
  }
});

test('new explicit type identifiers and direct characteristic reads cannot escape disclosure', () => {
  for (const expression of [
    'HKQuantityTypeIdentifier.heartRate.rawValue',
    'try healthStore.bloodType()',
  ]) {
    const result = findings((copy) => copy.set(manager, `${copy.get(manager)}\n${expression}`));
    assert.match(result[0]?.key ?? '', /Health Data disclosure (?:missing|mapping missing):/);
  }
});

test('new, removed and reclassified HealthKit types require questionnaire review', () => {
  for (const [before, after] of [
    ['.stepCount)!', '.heartRate)!'],
    ['dateOfBirthType, stepCountType]', 'dateOfBirthType]'],
    ['[weightType, bodyFatType]', '[weightType, bodyFatType, heightType]'],
    ['typesToRead)', 'Set<HKObjectType>())'],
  ]) {
    assert.notEqual(snapshot.get(manager).replace(before, after), snapshot.get(manager));
    assert.ok(
      findings((copy) => copy.set(manager, copy.get(manager).replace(before, after))).length,
    );
  }
});

test('a new HealthKit extension, constructor or permission owner cannot escape the inventory', () => {
  for (const [path, source] of [
    [
      'Services/HealthKitManager+Extra.swift',
      'var pulse: HKQuantityType { return HKQuantityType.quantityType(forIdentifier: .heartRate)! }',
    ],
    [
      'Services/HealthKitManager+Extra.swift',
      'let pulse = HKObjectType.quantityType(forIdentifier: .heartRate)',
    ],
    [
      'Services/AnotherHealthService.swift',
      'try await store.requestAuthorization(toShare: [], read: [])',
    ],
  ]) {
    assert.ok(findings((copy) => copy.set(`apps/ios/LogYourBody/${path}`, source)).length);
  }
});

test('changed, added, removed and non-string permission descriptions fail', () => {
  for (const change of [
    (source) => source.replace('read your weight', 'read your heart rate'),
    (source) =>
      source.replace(
        '<dict>',
        '<dict><key>NSLocationWhenInUseUsageDescription</key><string>Location</string>',
      ),
    (source) =>
      source.replace(/<key>NSHealthShareUsageDescription<\/key>\s*<string>[^<]*<\/string>/, ''),
    (source) =>
      source.replace(
        /(<key>NSHealthShareUsageDescription<\/key>)\s*<string>[^<]*<\/string>/,
        '$1<true/>',
      ),
  ])
    assert.ok(findings((copy) => copy.set(info, change(copy.get(info)))).length);
});

test('invalid, missing and incomplete questionnaire answers fail', () => {
  for (const change of [
    (answers) => {
      answers.dataTypes.pop();
    },
    (answers) => {
      delete answers.dataTypes[0].tracking;
    },
    (answers) => {
      delete answers.dataTypes[0].linkedToUser;
    },
    (answers) => {
      answers.dataCollected = false;
    },
    (answers) => {
      answers.dataTypes[0].tracking = true;
    },
    (answers) => {
      answers.ascComparison.status = 'confirmed';
    },
    (answers) => {
      answers.dataTypes[0].purposes = ['Unreviewed'];
    },
    (answers) => {
      answers.dataTypes[0].thirdPartyUse = [];
    },
    (answers) => {
      answers.healthKit[0].dataType = 'Unmapped';
    },
    (answers) => {
      answers.usageDescriptions.NSHealthShareUsageDescription.dataTypes = [];
    },
  ]) {
    assert.ok(
      findings((copy) => {
        const answers = JSON.parse(copy.get(QUESTIONNAIRE));
        change(answers);
        copy.set(QUESTIONNAIRE, JSON.stringify(answers));
      }).length,
    );
  }
  assert.ok(findings((copy) => copy.set(QUESTIONNAIRE, '{')).length);
});

test('a reviewed new HealthKit type passes only with matching disclosure and permissions', () => {
  assert.deepEqual(
    findings((copy) => {
      copy.set(manager, copy.get(manager).replace('.stepCount)!', '.heartRate)!'));
      const answers = JSON.parse(copy.get(QUESTIONNAIRE));
      const type = answers.healthKit.find((entry) => entry.identifier === 'stepCount');
      type.identifier = 'heartRate';
      type.dataType = 'Health';
      answers.dataTypes.find((entry) => entry.type === 'Health').data += '; heart rate';
      copy.set(QUESTIONNAIRE, JSON.stringify(answers));
      copy.set(policy, copy.get(policy).replace(/^- \*\*Health Data\*\*:.*$/m, '$&, heart rate'));
    }),
    [],
  );
});

test('formatting and comments do not change HealthKit authorization answers', () => {
  assert.deepEqual(
    findings((copy) =>
      copy.set(
        manager,
        `// HKQuantityType.quantityType(forIdentifier: .heartRate)\n${copy.get(manager)}`,
      ),
    ),
    [],
  );
});
