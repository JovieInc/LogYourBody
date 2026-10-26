import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import { scan } from './metric-card-control-owner.mjs';

const app = new URL('../../../apps/ios/LogYourBody/', import.meta.url);
const path = 'apps/ios/LogYourBody/MetricFixture.swift';
const check = (source) => scan({ files: [path], readSource: () => source });

test('retains a failing example of the old external metric-button owner', () => {
  const fixture = readFileSync(new URL('../src/fixtures/metric-card-external-button.swift.fixture', import.meta.url), 'utf8');
  assert.deepEqual(check(fixture), [{
    path, key: 'Button label wraps MetricSummaryCard; expected the card to own its control',
  }]);
  assert.equal(check(fixture + '\n' + fixture).length, 2);
  assert.deepEqual(check('Group {\n    MetricSummaryCard(detailAction: action)\n}'), []);
  assert.deepEqual(check('Button { save() } label: {\n    Text("Save")\n}'), []);
});

test('metric cards own their native buttons in every production caller (LYB-43)', () => {
  const swiftFiles = readdirSync(app, { recursive: true }).filter((file) => file.endsWith('.swift'));
  const sources = new Map(swiftFiles.map((file) => [
    `apps/ios/LogYourBody/${file}`, readFileSync(new URL(file, app), 'utf8'),
  ]));
  assert.deepEqual(scan({ files: [...sources.keys()], readSource: (file) => sources.get(file) }), []);
});

test('metric fixture does not write the read-only SwiftUI Reduce Motion environment', () => {
  const source = readFileSync(new URL('DesignSystem/Organisms/MetricSummaryCard.swift', app), 'utf8');
  assert.doesNotMatch(source, /\.environment\s*\(\s*\\\.accessibilityReduceMotion\b/);
});
