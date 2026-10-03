export default async function* report(source) {
  let covered = false;
  let failed = false;
  for await (const event of source) {
    if (event.type === 'test:fail') { failed = true; yield `${event.data.details?.error?.stack ?? 'test failure'}\n`; }
    if (event.type === 'test:pass' || event.type === 'test:fail') yield `${event.type}: ${event.data.name}\n`;
    if (event.type !== 'test:coverage') continue;
    const file = event.data.summary.files.find(f => f.path.endsWith('/preview-evidence.mjs'));
    if (!file) throw new Error('Preview checker was not instrumented');
    if (![file.coveredLinePercent, file.coveredBranchPercent, file.coveredFunctionPercent].every(Number.isFinite) || ![file.totalLineCount, file.totalBranchCount, file.totalFunctionCount].every(n => Number.isInteger(n) && n > 0)) {
      throw new Error('Invalid or empty checker coverage');
    }
    covered = true;
    yield `Preview checker coverage: ${JSON.stringify(file)}\n`;
    if (file.coveredLinePercent < 95 || file.coveredBranchPercent < 90 || file.coveredFunctionPercent < 100) {
      throw new Error('Preview checker coverage below 95% lines / 90% branches / 100% functions');
    }
  }
  if (!covered || failed) throw new Error('Preview tests/coverage did not pass');
}
