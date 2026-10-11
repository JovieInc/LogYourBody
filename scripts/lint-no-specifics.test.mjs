import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { containsForbiddenIdentity, parseDenylist } from './lint-no-specifics.mjs';

test('hashed identity linter matches normalized text without storing the identity', () => {
  const identity = 'futurechannel';
  const digest = createHash('sha256').update(identity).digest('hex');
  const entries = parseDenylist(identity.length + '\t' + digest + '\n');

  assert.equal(containsForbiddenIdentity('Future Channel training guide', entries), true);
  assert.equal(containsForbiddenIdentity('An unrelated training guide', entries), false);
  assert.equal(JSON.stringify(entries).includes(identity), false);
});

test('hashed identity linter rejects malformed and empty hash lists', () => {
  assert.throws(() => parseDenylist(''), /empty/);
  assert.throws(() => parseDenylist('futurechannel\n'), /Invalid/);
});
