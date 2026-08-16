import { defineEval } from 'eve/evals';
import { equals } from 'eve/evals/expect';

export default defineEval({
  description: 'Exercise the local runtime without credentials or side effects.',
  tags: ['smoke'],
  async test(t) {
    const first = await t.send('first private-safe smoke message');
    t.check(first.message, equals('LYB local smoke turn 1: first private-safe smoke message'));

    const second = await t.send('second private-safe smoke message');
    await t.require(second.sessionId, equals(first.sessionId));
    t.check(second.message, equals('LYB local smoke turn 2: second private-safe smoke message'));

    t.succeeded();
    t.usedNoTools();
    t.noFailedActions();
  },
});
