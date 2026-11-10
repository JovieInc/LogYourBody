export const LEVELS: readonly ['codebase', 'static', 'prose', 'human', 'unclassified'];
export type CorrectionLevel = Exclude<(typeof LEVELS)[number], 'unclassified'>;
export type CorrectionAssessment = { feasible: boolean; rationale: string };
export type CorrectionClassification = Partial<Record<CorrectionLevel, CorrectionAssessment>>;

interface CorrectionInput {
  fingerprint: string;
  level?: CorrectionLevel | 'unclassified';
  classification?: CorrectionClassification;
}

interface ClassificationResult {
  level: CorrectionLevel;
  rationale: string;
  considered: (CorrectionAssessment & { level: CorrectionLevel })[];
}

export function classifyCorrection(receipt: CorrectionInput, required: true): ClassificationResult;
export function classifyCorrection(
  receipt: CorrectionInput,
  required?: false,
): Omit<ClassificationResult, 'level' | 'rationale'> & {
  level: CorrectionLevel | 'unclassified';
  rationale: string | null;
};
