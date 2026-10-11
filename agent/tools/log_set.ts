import { defineTool } from 'eve/tools';
import { z } from 'zod';
import { trainingToolGate } from '../lib/training-tools';

const Input = z.object({
  sessionId: z.string().uuid(),
  exerciseId: z.string().trim().min(1).max(64),
  setNumber: z.number().int().min(1).max(10),
  reps: z.number().int().min(1).max(50),
  loadKg: z.number().finite().min(0).max(500).nullable(),
  rir: z.number().int().min(0).max(6),
}).strict();

const Output = z.object({
  available: z.literal(false),
  status: z.enum(['connection_required', 'first_party_auth_required']),
});

export default defineTool({
  description: 'Record a completed set against an active engine-generated session after first-party authorization is available.',
  inputSchema: Input,
  outputSchema: Output,
  execute(_input, context) {
    return trainingToolGate(context.session.auth.current);
  },
});
