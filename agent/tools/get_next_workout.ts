import { defineTool } from 'eve/tools';
import { z } from 'zod';
import { trainingToolGate } from '../lib/training-tools';

const Output = z.object({
  available: z.literal(false),
  status: z.enum(['connection_required', 'first_party_auth_required']),
});

export default defineTool({
  description: 'Return the next engine-generated session for an opted-in, connected account when first-party authorization is available.',
  inputSchema: z.object({}),
  outputSchema: Output,
  execute(_input, context) {
    return trainingToolGate(context.session.auth.current);
  },
});
