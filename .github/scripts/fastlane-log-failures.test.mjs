import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fastlaneFailureLines } from './fastlane-log-failures.mjs';

const changelog = [
  '#######################################################################',
  '# fastlane 2.241.1 is available. You are on 2.240.1.',
  '#######################################################################',
  '\u001b[32m2.241.0 Improvements\u001b[0m',
  "* [action] clean_build_artifacts: say that cert's private key and signing request are kept (#30347) via Jerome Lacoste (@lacostej)",
  '* [meta] remove duplicate contact link for security submission (#30349) via Connor Tumbleson (@iBotPeaches)',
  '* [docs] Testing.md: a spec for a fix has to fail without the fix (#30333) via Jerome Lacoste (@lacostej)',
  '* [spaceship] Assert the error class instead of negating a different one (#30234) via Jerome Lacoste (@lacostej)',
  '* Fix `Raise` typo in Device validation guard: Error: FAILED (#30255)',
].join('\n');

test('ignores fastlane changelog lines on a clean run', () => {
  const log = [
    '[19:24:00]: Creating authorization token for App Store Connect API',
    '[19:24:05]: precheck 👮‍♀️ 👮  finished without detecting any potential problems 🛫',
    changelog,
  ].join('\n');
  assert.deepEqual(fastlaneFailureLines(log), []);
});

test('flags the precheck API-key in-app purchase abort', () => {
  const log = [
    '\u001b[31m',
    '[!] Precheck cannot check In-app purchases with the App Store Connect API Key (yet). Exclude In-app purchases from precheck, disable the precheck step in your build step, or use Apple ID login\u001b[0m',
    changelog,
  ].join('\n');
  assert.deepEqual(fastlaneFailureLines(log), [
    '[!] Precheck cannot check In-app purchases with the App Store Connect API Key (yet). Exclude In-app purchases from precheck, disable the precheck step in your build step, or use Apple ID login',
  ]);
});

test('flags precheck rule failures', () => {
  const log = [
    '+--------------+',
    '| Failed rules |',
    '+--------------+',
    '[10:00:00]: \u001b[31mprecheck 👮‍♀️ 👮  found one or more potential problems that must be addressed before submitting to review\u001b[0m',
  ].join('\n');
  assert.equal(fastlaneFailureLines(log).length, 2);
});

test('flags Apple upload rejections', () => {
  const log = '[10:00:00]: ERROR ITMS-90189: "Redundant Binary Upload."';
  assert.deepEqual(fastlaneFailureLines(log), ['ERROR ITMS-90189: "Redundant Binary Upload."']);
});

test('handles empty input', () => {
  assert.deepEqual(fastlaneFailureLines(''), []);
  assert.deepEqual(fastlaneFailureLines(undefined), []);
});
