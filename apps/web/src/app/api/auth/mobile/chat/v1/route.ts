import { randomUUID } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { createChatModelPort } from '@/lib/adapters/openai-chat-model-adapter';
import { fetchUserInfo } from '@/lib/auth/jovie-oauth';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';
import { neonChatConversations } from '@/lib/neon/chat-conversations-adapter';
import { neonUserDirectory } from '@/lib/neon/user-directory-adapter';
import { neonNativeProductRecords } from '@/lib/neon/native-product-records-adapter';
import { getOrCreateNextWorkout } from '@/lib/training/service';
import { createChatRouteHandlers } from './route-handlers';
import { delegatedProgrammingEnabled } from '@/lib/flags/delegated-programming';
import { neonTrainingRevisions } from '@/lib/neon/training-revisions-adapter';
import { createDelegatedProposal } from '@/lib/training/delegated-revisions';
import { interpretSteering } from '@/lib/training/delegated-planning';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function authenticate(request: NextRequest) {
  const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  return token ? fetchUserInfo(token) : null;
}

const handlers = createChatRouteHandlers({
  authenticate,
  conversations: neonChatConversations,
  bodyMetrics: neonBodyMetrics,
  users: neonUserDirectory,
  createModel: createChatModelPort,
  modelName: process.env.LYB_CHAT_MODEL || 'gpt-4o-mini',
  createLeaseToken: randomUUID,
  reportStreamOutcome: (outcome) => console.info('LYB_CHAT_STREAM', { outcome }),
  proposeTrainingSteering: async ({ subject, requestId, utterance }) => {
    if (!delegatedProgrammingEnabled() || !interpretSteering(utterance)) return null;
    const context = await neonTrainingRevisions.readContext(subject);
    if (!context)
      return { content: 'Your training account could not be read. No plan change was applied.' };
    const result = await createDelegatedProposal({
      revisions: neonTrainingRevisions,
      records: neonNativeProductRecords,
      subject,
      actor: { kind: 'user', subject },
      now: new Date(),
      body: { requestId, expectedGeneration: context.generation, reason: utterance, utterance },
    });
    if (result.kind === 'stored' && result.stored.proposal.version === 2) {
      const proposal = result.stored.proposal;
      const stringDiff = proposal.proposedDiff.flatMap((item) => {
        if (typeof item.before !== 'string' || typeof item.after !== 'string') return [];
        const label = item.field.trim().slice(0, 80);
        const from = item.before.trim().slice(0, 120);
        const to = item.after.trim().slice(0, 120);
        return label ? [{ label, from, to }] : [];
      });
      const changing = proposal.transition?.changing ?? [];
      return {
        content: `Draft ready for review. ${proposal.summary.join(' ')} Open Review training plan to inspect and apply it. Your saved plan has not changed.`,
        proposalId: proposal.id,
        revisionId: proposal.baseRevision,
        reason: proposal.reason,
        diff:
          stringDiff.length > 0
            ? stringDiff
            : changing.map((text) => ({ label: 'Change', from: '', to: text })),
        reasons: proposal.summary,
        evidenceIds: proposal.inputEvidence.evidenceIds,
        status: result.stored.status === 'proposed' ? 'pending' : result.stored.status,
      };
    }
    if (result.kind === 'question') return { content: result.question };
    return {
      content: `No plan change was applied (${result.kind}). Review your current training plan before retrying.`,
    };
  },
  getTrainingOutput: async (subject) => {
    if (process.env.LYB_HYPERTROPHY_COACH_API_ENABLED !== 'true') return null;
    return getOrCreateNextWorkout({
      records: neonNativeProductRecords,
      subject,
      now: new Date(),
      persist: !delegatedProgrammingEnabled(),
    });
  },
});

export const GET = handlers.GET;
export const POST = handlers.POST;
export const DELETE = handlers.DELETE;
