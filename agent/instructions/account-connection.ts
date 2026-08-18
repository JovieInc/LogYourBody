import { defineDynamic, defineInstructions } from 'eve/instructions';
import {
  connectionInstruction,
  connectionStateFromAttributes,
  localConnectionFixture,
} from '../lib/account-connection';

export default defineDynamic({
  events: {
    'session.started': (_event, ctx) => {
      const state =
        process.env.LYB_EVE_LOCAL_SMOKE === '1'
          ? localConnectionFixture()
          : connectionStateFromAttributes(ctx.session.auth.current?.attributes);

      return defineInstructions({ markdown: connectionInstruction(state) });
    },
  },
});
