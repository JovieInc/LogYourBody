// Core Data rejects a saved cache row whose required lastModified is still nil.
export function savedCacheRowsMissingLastModified(source: string): string[] {
  const cleaned = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  const findings: string[] = [];
  const header =
    /\n(?=[ \t]*(?:@\w+[ \t]+)*(?:(?:private|fileprivate|internal|public|open|override|static|final)[ \t]+)*func[ \t]+)/;
  for (const body of cleaned.split(header)) {
    const name = body.match(/\bfunc[ \t]+(\w+)/)?.[1] ?? 'file';
    const creates =
      /\b(?:let|var)[ \t]+(\w+)[ \t]*=[ \t]*Cached(?:Body|Daily)Metrics\s*\(\s*context\s*:/g;
    for (const create of body.matchAll(creates)) {
      const variable = create[1];
      const after = body.slice((create.index ?? 0) + create[0].length);
      const saveAt = after.search(/\b(?:try[!?]?\s+)?(?:await\s+)?[\w.]+\.save\s*\(/);
      if (saveAt < 0) continue;
      const span = after.slice(0, saveAt);
      const mentions = (pattern: string) => new RegExp(pattern).test(span);
      const ready =
        mentions(`\\b${variable}\\.lastModified\\b`) ||
        mentions(`\\.delete\\s*\\(\\s*${variable}\\s*\\)`) ||
        (mentions(`\\b${variable}\\.setValuesForKeys\\b`) && mentions('attributesByName')) ||
        (mentions(`\\b${variable}\\.setValue\\b`) && mentions('lastModified'));
      if (!ready) findings.push(`${name}: ${variable} is saved without lastModified`);
    }
  }
  return findings;
}
