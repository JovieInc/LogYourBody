import { mesocycleOptimizerEnabled } from '@/lib/flags/mesocycle-optimizer';
import { certifyOptimization } from './optimizer-certification';
import { optimizeMesocycle, type OptimizationChange, type OptimizationProposal } from './optimizer';
import { OPTIMIZER_EVIDENCE_VERSION, OPTIMIZER_RULES } from './optimizer-rules';
import { createProposalInputSchema } from './revision-contract';
import { trainingRequestHash } from './revisions';

/**
 * Review gate for a mesocycle optimization.
 * Applying accepts the diff for a person to confirm. It does not enroll a
 * program and it does not write over a plan: the enrollment command refuses a
 * second program once a head revision exists, and a user edit fails this gate.
 */
export type OptimizationReceipt = {
  version: 1;
  kind: 'mesocycle_optimization';
  decision: 'apply' | 'reject';
  status: 'accepted' | 'rejected';
  authority: 'self_review_required';
  evidenceVersion: string;
  requestHash: string;
  writesPerformed: false;
  enrollment: false;
};

export type OptimizationDecision =
  | { kind: 'disabled' }
  | { kind: 'invalid' }
  | { kind: 'rejected'; receipt: OptimizationReceipt }
  | { kind: 'stale_evidence' }
  | { kind: 'user_edit_conflict' }
  | { kind: 'not_certified'; violations: string[] }
  | { kind: 'accepted'; receipt: OptimizationReceipt; changes: OptimizationChange[] };

function receipt(
  proposal: OptimizationProposal,
  decision: 'apply' | 'reject',
  currentFingerprint: string,
): OptimizationReceipt {
  return {
    version: 1,
    kind: 'mesocycle_optimization',
    decision,
    status: decision === 'apply' ? 'accepted' : 'rejected',
    authority: 'self_review_required',
    evidenceVersion: proposal.evidenceVersion,
    requestHash: trainingRequestHash({
      proposalId: proposal.id,
      decision,
      currentFingerprint,
      evidenceVersion: proposal.evidenceVersion,
    }),
    writesPerformed: false,
    enrollment: false,
  };
}

export function decideMesocycleOptimization(input: {
  source: unknown;
  proposal: OptimizationProposal;
  decision: 'apply' | 'reject';
  currentFingerprint: string;
  currentEvidenceVersion?: string;
  enabled: boolean;
}): OptimizationDecision {
  if (!input.enabled) return { kind: 'disabled' };
  if (input.decision !== 'apply' && input.decision !== 'reject') return { kind: 'invalid' };
  if (input.decision === 'reject') {
    return {
      kind: 'rejected',
      receipt: receipt(input.proposal, 'reject', input.currentFingerprint),
    };
  }
  const currentVersion = input.currentEvidenceVersion ?? OPTIMIZER_EVIDENCE_VERSION;
  if (
    input.proposal.evidenceVersion !== OPTIMIZER_EVIDENCE_VERSION ||
    currentVersion !== input.proposal.evidenceVersion
  ) {
    return { kind: 'stale_evidence' };
  }
  if (input.currentFingerprint !== input.proposal.baseFingerprint) {
    return { kind: 'user_edit_conflict' };
  }
  const verdict = certifyOptimization(input.source, input.proposal, OPTIMIZER_RULES);
  if (!verdict.ok) return { kind: 'not_certified', violations: verdict.violations };
  return {
    kind: 'accepted',
    receipt: receipt(input.proposal, 'apply', input.currentFingerprint),
    changes: input.proposal.changes,
  };
}

export function optimizerRequestIsEnrollment(body: unknown): boolean {
  return createProposalInputSchema.safeParse(body).success;
}

export function proposeMesocycleOptimization(body: unknown, enabled = mesocycleOptimizerEnabled()) {
  if (!enabled) return { kind: 'disabled' as const };
  const result = optimizeMesocycle(body);
  if (result.kind !== 'proposal') return { kind: 'invalid' as const };
  const verdict = certifyOptimization(body, result.proposal);
  if (!verdict.ok) return { kind: 'not_certified' as const, violations: verdict.violations };
  return { kind: 'proposal' as const, proposal: result.proposal, persisted: false as const };
}
