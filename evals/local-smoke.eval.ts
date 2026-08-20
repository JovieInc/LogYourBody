import { defineEval } from 'eve/evals';
import { equals } from 'eve/evals/expect';
import { localConnectionFixture, smokeReply } from '../agent/lib/account-connection';

export default defineEval({
  description: 'Exercise the core chat account boundary without credentials or side effects.',
  tags: ['smoke'],
  async test(t) {
    const state = localConnectionFixture();
    const first = await t.send('How is my health trend?');
    t.check(first.message, equals(smokeReply(state, 1)));

    const second = await t.send('What should I do next?');
    await t.require(second.sessionId, equals(first.sessionId));
    t.check(second.message, equals(smokeReply(state, 2)));

    t.succeeded();
    t.usedNoTools();
    t.noFailedActions();
  },
});
