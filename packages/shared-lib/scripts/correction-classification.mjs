import assert from 'node:assert/strict';

export const LEVELS = ['codebase', 'static', 'prose', 'human', 'unclassified'];

export function classifyCorrection(receipt, required) {
  const assessments = receipt.classification;
  if (assessments === undefined) {
    assert.ok(!required, `classification required: ${receipt.fingerprint}`);
    // Retain old annotations when reading immutable coverage baselines.
    return { level: receipt.level ?? 'unclassified', rationale: null, considered: [] };
  }
  const levels = LEVELS.slice(0, -1);
  assert.ok(
    assessments &&
      typeof assessments === 'object' &&
      !Array.isArray(assessments) &&
      Object.keys(assessments).every((level) => levels.includes(level)),
    'invalid correction classification',
  );
  const considered = [];
  for (const level of levels) {
    const assessment = assessments[level];
    assert.ok(
      typeof assessment?.feasible === 'boolean' &&
        typeof assessment.rationale === 'string' &&
        assessment.rationale.trim(),
      `classification assessment required for ${level}: ${receipt.fingerprint}`,
    );
    const rationale = assessment.rationale.trim();
    considered.push({ level, feasible: assessment.feasible, rationale });
    if (assessment.feasible) {
      assert.ok(
        receipt.level === undefined || receipt.level === level,
        `correction level conflicts with lowest enforceable level: ${receipt.fingerprint}`,
      );
      return { level, rationale, considered };
    }
  }
  throw new Error(`no enforceable correction level: ${receipt.fingerprint}`);
}
