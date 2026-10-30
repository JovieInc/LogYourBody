const FORBIDDEN = [
  'setWidgetState',
  'sendFollowUpMessage',
  'uploadFile',
  'privateContent',
  'modelContent',
  'imageIds',
  'innerHTML',
];

const HEALTH_NEAR_CALL = /\b(bodyFat|body_fat|weightKg|leanMass|imageUrl|weighIns|photoId|ph_)\b/;

/** Fails closed if the widget bundle can place health values where the model can read them. */
export function auditHealthVaultWidgetBundle(source: string): string[] {
  const violations: string[] = [];
  for (const name of FORBIDDEN) {
    if (source.includes(name)) violations.push(name);
  }
  const calls = source.match(/callTool\s*\(/g) ?? [];
  if (calls.length !== 1) violations.push(`callTool count ${calls.length}`);
  const match = /callTool\s*\(/.exec(source);
  if (match) {
    const slice = source.slice(match.index, match.index + 220);
    if (!slice.includes('share_summary_with_chatgpt') || !slice.includes('consentId')) {
      violations.push('callTool must pass only a consent id to share_summary_with_chatgpt');
    }
    if (HEALTH_NEAR_CALL.test(slice)) violations.push('callTool includes a health value');
  }
  return violations;
}
