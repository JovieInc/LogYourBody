import type { SwapConstraints } from '@/lib/training/commands';
import type {
  DelegatedProgram,
  ProgramSteeringRecord,
  SteeringHealthDecision,
} from '@/lib/training/delegation-contract';

/** Trusted policy boundary, never a decision supplied by conversational text. */
export interface SteeringHealthPolicyPort {
  evaluate(input: {
    subject: string;
    program: DelegatedProgram;
    record: ProgramSteeringRecord;
  }): Promise<SteeringHealthDecision>;
}

/** LYB-113 owns handling these requests. It must deduplicate subject + revisionId
 * and reject a request whose program revision is no longer current.
 * A request does not edit a workout or claim a substitution has been applied. */
export interface SteeringMovementRequestsPort {
  request(input: {
    subject: string;
    programId: string;
    revisionId: string;
    constraintId: string;
    constraints: Pick<SwapConstraints, 'maxTrunkDemand' | 'excludedConcerns'>;
  }): Promise<void>;
}
