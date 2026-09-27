import { defineTool } from 'eve/tools';
import { z } from 'zod';
import { trainingToolGate } from '../lib/training-tools';

const Input = z.object({
  sessionId: z.string().uuid(),
  soreness: z.number().int().min(0).max(10),
  pump: z.number().int().min(0).max(10),
  performance: z.enum(['up', 'stable', 'down']),
  jointPain: z.number().int().min(0).max(10),
}).strict();

const Output = z.object({
  available: z.literal(false),
  status: z.enum(['connection_required', 'first_party_auth_required']),
});

export default defineTool({
  description: 'Record session recovery feedback for engine decisions after first-party authorization is available.',
  inputSchema: Input,
  outputSchema: Output,
  execute(_input, context) {
    return trainingToolGate(context.session.auth.current);
  },
});
