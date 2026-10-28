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
const snapshot = new Map(
  files.map((path) => [
    path,
    /\.swift$/.test(path) || path === info || path === QUESTIONNAIRE
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
