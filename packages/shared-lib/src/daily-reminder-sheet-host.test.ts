import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const ancestorSheet = '.sheet(isPresented: $showDailyReminderOffer';

/**
 * The daily reminder sheet has to be a sibling of Today. A `.sheet` modifier
 * on `MainTabView` is an ancestor of the edit-entry sheet, and SwiftUI then
 * drops that presentation. Launch quality caught it in
 * `testWeightEntryPhotoImportControlsAreExcludedFromMonkeyCandidates`:
 * Edit entry was tapped, Context stayed up, and `home_v2_log_sheet` never
 * appeared.
 */
export function dailyReminderSheetHostProblem(source: string): string | null {
  if (source.includes(ancestorSheet)) {
    return 'daily reminder sheet wraps Today through $showDailyReminderOffer';
  }

  const hostStart = source.indexOf('struct DailyReminderOfferSheetHost');
  if (hostStart < 0) {
    return 'missing DailyReminderOfferSheetHost';
  }
  const nextStructAt = source.indexOf('\nstruct ', hostStart + 1);
  const host = source.slice(hostStart, nextStructAt === -1 ? source.length : nextStructAt);
  if (!host.includes('.sheet(isPresented: $isPresented')) {
    return 'DailyReminderOfferSheetHost does not present the sheet';
  }
  // The anchor must not cover pushed controls. Apply these modifiers before
  // .sheet so the presented reminder remains visible and interactive.
  const anchor = host.split('.sheet(isPresented: $isPresented')[0];
  if (!/Color\.clear\s*\.frame\(width: 0, height: 0\)\s*\.allowsHitTesting\(false\)/.test(anchor)) {
    return 'daily reminder presentation anchor must be zero-sized and noninteractive';
  }

  const backgroundAt = source.lastIndexOf('.background {', hostStart);
  if (backgroundAt < 0) {
    return 'DailyReminderOfferSheetHost is not installed from a background sibling';
  }
  const installed = source.slice(backgroundAt, hostStart);
  if (!installed.includes('DailyReminderOfferSheetHost(')) {
    return 'background sibling does not install DailyReminderOfferSheetHost';
  }
  if (!installed.includes('isPresented: $showDailyReminderOffer')) {
    return 'background host is not bound to showDailyReminderOffer';
  }
  if (installed.includes('MainTabView(')) {
    return 'background host wraps MainTabView';
  }
  if (source.lastIndexOf('MainTabView(', backgroundAt) < 0) {
    return 'MainTabView missing';
  }
  return null;
}

const brokenHost = `
MainTabView(releaseReviewDestination: $releaseReviewDestination)
    .onAppear { showDailyReminderOffer = shouldShowDailyReminderPrompt }
    .sheet(isPresented: $showDailyReminderOffer, onDismiss: {}) {
        DailyWeighInReminderPromptView(notificationManager: notificationManager) {}
    }
`;

const siblingHost = `
MainTabView(releaseReviewDestination: $releaseReviewDestination)
    .onAppear { showDailyReminderOffer = shouldShowDailyReminderPrompt }
    .background {
        DailyReminderOfferSheetHost(
            isPresented: $showDailyReminderOffer,
            notificationManager: notificationManager,
            onDismiss: {}
        )
    }
struct DailyReminderOfferSheetHost: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                DailyWeighInReminderPromptView(notificationManager: notificationManager) {}
            }
    }
}
`;

it('rejects a daily reminder sheet that wraps Today', () => {
  expect(dailyReminderSheetHostProblem(brokenHost)).toBe(
    'daily reminder sheet wraps Today through $showDailyReminderOffer',
  );
});

it('accepts a daily reminder sheet hosted beside Today', () => {
  expect(dailyReminderSheetHostProblem(siblingHost)).toBeNull();
});

it('rejects a full-screen or interactive reminder anchor over pushed controls', () => {
  for (const modifier of ['.frame(width: 0, height: 0)', '.allowsHitTesting(false)']) {
    expect(dailyReminderSheetHostProblem(siblingHost.replace(modifier, ''))).toBe(
      'daily reminder presentation anchor must be zero-sized and noninteractive',
    );
  }
});

it('does not disable hit testing on the presented reminder content', () => {
  const disabledSheet = siblingHost
    .replace('            .allowsHitTesting(false)\n', '')
    .replace('\n    }\n}\n', '\n            .allowsHitTesting(false)\n    }\n}\n');
  expect(dailyReminderSheetHostProblem(disabledSheet)).toBe(
    'daily reminder presentation anchor must be zero-sized and noninteractive',
  );
});

it('hosts the daily reminder sheet beside Today in ContentView', () => {
  const source = readFileSync(
    fileURLToPath(new URL('../../../apps/ios/LogYourBody/ContentView.swift', import.meta.url)),
    'utf8',
  );
  expect(dailyReminderSheetHostProblem(source)).toBeNull();
});

/** A pushed screen must own the sheet its controls present. */
function contextEditSheetHostProblem(source: string): string | null {
  const context = source
    .split('.navigationDestination(isPresented: $isHomeV2ContextPresented) {')[1]
    ?.split('.navigationDestination(isPresented: $isHomeV2EntriesPresented) {')[0];
  const sheet = '.sheet(item: $homeV2EditingSession)';
  const visibleHost =
    /^\s*homeV2ContextView\s*\.sheet\(item: \$homeV2EditingSession\) \{ session in\s*homeV2EditEntrySheet\(for: session\)/;
  if (!context || !visibleHost.test(context)) {
    return 'Context must host its edit-entry sheet on the visible navigation destination';
  }
  if (source.split(sheet).length !== 2) {
    return 'Context must have exactly one edit-entry sheet presenter';
  }
  return null;
}

const contextHost = `
    .navigationDestination(isPresented: $isHomeV2ContextPresented) {
        homeV2ContextView
            .sheet(item: $homeV2EditingSession) { session in
                homeV2EditEntrySheet(for: session)
            }
    }
    .navigationDestination(isPresented: $isHomeV2EntriesPresented) {
        homeV2EntriesView
    }
`;

it('rejects the edit-entry presenter on the covered timeline root', () => {
  const sheet = `.sheet(item: $homeV2EditingSession) { session in
                homeV2EditEntrySheet(for: session)
            }`;
  expect(contextEditSheetHostProblem(sheet + contextHost.replace(sheet, ''))).toBe(
    'Context must host its edit-entry sheet on the visible navigation destination',
  );
  const rootHost = contextHost
    .replace(sheet, '')
    .replace(
      '.navigationDestination(isPresented: $isHomeV2EntriesPresented)',
      sheet + '\n.navigationDestination(isPresented: $isHomeV2EntriesPresented)',
    );
  expect(contextEditSheetHostProblem(rootHost)).toBe(
    'Context must host its edit-entry sheet on the visible navigation destination',
  );
});

it('accepts one edit-entry presenter owned by Context and rejects duplicates', () => {
  expect(contextEditSheetHostProblem(contextHost)).toBeNull();
  expect(contextEditSheetHostProblem(contextHost + contextHost)).toBe(
    'Context must have exactly one edit-entry sheet presenter',
  );
});

it('keeps the edit-entry presenter on the visible Context destination', () => {
  const source = readFileSync(
    new URL(
      '../../../apps/ios/LogYourBody/Views/DashboardViewLiquid+PhotoTimelineHUD.swift',
      import.meta.url,
    ),
    'utf8',
  );
  expect(contextEditSheetHostProblem(source)).toBeNull();
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  expect(turbo.tasks.test.inputs).toContain(
    '$TURBO_ROOT$/apps/ios/LogYourBody/Views/DashboardViewLiquid+PhotoTimelineHUD.swift',
  );
});
