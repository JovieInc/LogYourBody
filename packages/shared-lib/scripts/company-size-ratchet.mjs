// Company size-500 ratchet. Same count, extensions and skip rules as
// JovieInc/ci guards/size.mjs. Baselined files may not grow. New files over
// 500 lines fail. Read only the supplied snapshot.
export const LIMIT = 500;
const CODE = /\.(ts|tsx|js|jsx|mjs|cjs|py|swift|ex|exs|sh|rb|go|rs)$/;
const SKIP = /(^|\/)(node_modules|vendor|dist|build|\.next|Pods)\/|\.gen\.|\.generated\.|\.min\.|\.d\.ts$|lock/;
export const BASELINE_PATH = '.company-guards/size-baseline.json';

export function lineCount(text) {
  return text.split('\n').length - (text.endsWith('\n') ? 1 : 0);
}

export function scan({ files, readSource }) {
  const baseline = JSON.parse(readSource(BASELINE_PATH));
  const findings = [];
  for (const path of files) {
    if (path === BASELINE_PATH || !CODE.test(path) || SKIP.test(path)) continue;
    let text;
    try {
      text = readSource(path);
    } catch {
      continue;
    }
    if (typeof text !== 'string') continue;
    const lines = lineCount(text);
    if (lines <= LIMIT) continue;
    if (!Object.hasOwn(baseline, path)) {
      findings.push({ path, key: `${path}: ${lines} lines, over ${LIMIT} and not baselined` });
    } else if (lines > baseline[path]) {
      findings.push({ path, key: `${path}: grew ${baseline[path]} -> ${lines}` });
    }
  }
  return findings;
}
