import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const app = new URL('../../../apps/ios/LogYourBody/', import.meta.url);
const source = (path: string) => readFileSync(new URL(path, app), 'utf8');

// JovieInc/Jovie#21838, docs/product/lyb-launch-contract.md at
// 197a96ff21c53cb4ccd8f6c1e3d733058b8c1cf7. Dates guide planning, never guarantee a result.
const approved = {
  headline: 'Your body-composition goal, planned around your next date.',
  explanation:
    'Set an outcome and a date. LogYourBody follows your photos and measurements, spots drift, and gives you one next action.',
  framing: 'Dates guide the plan. They do not guarantee a result.',
};

const launchSources = [
  'Views/LoginView.swift',
  'Views/HomeV2/HomeV2OnboardingViews.swift',
  'Views/PaywallView.swift',
  'Services/LaunchJourney.swift',
  'Services/LaunchJourneyUI.swift',
  ...readdirSync(new URL('Features/Onboarding/Views/', app))
    .filter((name) => name.endsWith('.swift'))
    .map((name) => `Features/Onboarding/Views/${name}`),
];

function resultPromises(text: string) {
  const literals = [...text.matchAll(/"((?:\\.|[^"\\])*)"/g)].map((match) => match[1]);
  return literals.filter((literal) => {
    if (Object.values(approved).includes(literal)) return false;
    const normalized = literal.normalize('NFKC').replace(/[’‘]/g, "'").replace(/[-_]/g, ' ');
    return [
      /\b(?:guarantee\w*|promise\w*)\b[^.!?]*\b(?:results?|body|weight|fat|muscle|lean)\b/i,
      /\b(?:lose|losing|lost|shed|burn\w*|drop\w*|reduc\w*)\b[^.!?]*\b(?:fat|weight|pounds?|lbs?|kg|kilograms?)\b/i,
      /\b(?:build\w*|gain\w*|grow\w*|increas\w*)\b[^.!?]*\b(?:muscle|lean mass)\b/i,
      /\b(?:reach|achieve|hit|deliver\w*)\b[^.!?]*\b(?:goal|target|body|physique|body composition)\b/i,
      /\b(?:get|become|you'll be|you will be)\b[^.!?]*\b(?:leaner|slimmer|muscular|shredded)\b/i,
      /\btransform\w*\b[^.!?]*\b(?:body|physique)\b/i,
    ].some((claim) => claim.test(normalized));
  });
}

describe('LYB-286 approved date-driven launch promise', () => {
  it('keeps the app copy table exactly equal to the approved strings', () => {
    const table = source('Services/LaunchJourney.swift').match(
      /enum LaunchPromiseCopy \{([^}]+)\}/,
    )?.[1];
    expect(table).toBeDefined();
    const entries = [...(table ?? '').matchAll(/static let (\w+)\s*=\s*"([^"]+)"/g)];
    expect(Object.fromEntries(entries.map((entry) => [entry[1], entry[2]]))).toEqual(approved);
  });

  it('uses the table on both sign-in paths, the first data screen, coach welcome and date editor', () => {
    for (const path of [
      'Views/LoginView.swift',
      'Features/Onboarding/Views/BodyScoreHookView.swift',
    ]) {
      expect(source(path)).toMatch(/title:\s*LaunchPromiseCopy\.headline\s*,/);
      expect(source(path)).toMatch(/subtitle:\s*LaunchPromiseCopy\.explanation\s*[,\n]/);
    }
    const signIn = source('Views/HomeV2/HomeV2OnboardingViews.swift');
    expect(signIn).toMatch(/static let signInTitle = LaunchPromiseCopy\.headline\s/);
    expect(signIn).toMatch(/static let signInBody = LaunchPromiseCopy\.explanation\s/);
    expect(signIn).toContain('Text(HomeV2OnboardingCopy.signInTitle)');
    expect(signIn).toContain('Text(HomeV2OnboardingCopy.signInBody)');
    expect(source('Views/MainTabView.swift')).toContain(
      'text: "\\(LaunchPromiseCopy.headline) \\(LaunchPromiseCopy.explanation)",',
    );
    expect(source('Services/LaunchJourneyUI.swift')).toContain('Text(LaunchPromiseCopy.framing)');
    expect(source('Services/LaunchJourney.swift')).toContain(
      'Action(title: "Set an outcome and a date", detail: LaunchPromiseCopy.explanation)',
    );
  });

  it('has no other launch string promising a body-composition result', () => {
    for (const path of launchSources) {
      expect(resultPromises(source(path)), path).toEqual([]);
    }
    const welcome = source('Views/MainTabView.swift')
      .split('static let welcome = ChatMessage(')[1]
      ?.split('\n    )')[0];
    expect(welcome).toBeDefined();
    expect(resultPromises(welcome ?? '')).toEqual([]);
  });

  it.each([
    'You will lose fat by your date.',
    'Build muscle by your next shoot.',
    "You'll be leaner by summer.",
    'Reach your body-composition goal on time.',
    'Guaranteed results by your date.',
    'Transform your body before travel.',
  ])('rejects a result promise added to a launch screen: %s', (claim) => {
    const screen = `${source('Views/LoginView.swift')}\nText("${claim}")`;
    expect(resultPromises(screen)).toContain(claim);
  });
});
