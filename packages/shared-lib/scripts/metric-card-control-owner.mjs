// LYB-43: keep metric controls inside the card, never inside an external Button.
// Read only the supplied snapshot so the required ratchet also audits immutable Git source.
export function scan({ files, readSource }) {
  return files
    .filter((path) => path.startsWith('apps/ios/LogYourBody/') && path.endsWith('.swift'))
    .flatMap((path) =>
      Array.from(readSource(path).matchAll(/\bButton\s*\{[\s\S]*?\}\s*label:\s*\{([\s\S]*?)^\s*\}/gm))
        .filter((match) => match[1].includes('MetricSummaryCard('))
        .map(() => ({ path, key: 'Button label wraps MetricSummaryCard; expected the card to own its control' })),
    );
}
