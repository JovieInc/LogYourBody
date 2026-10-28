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

it('hosts the daily reminder sheet beside Today in ContentView', () => {
  const source = readFileSync(
    fileURLToPath(new URL('../../../apps/ios/LogYourBody/ContentView.swift', import.meta.url)),
    'utf8',
  );
  expect(dailyReminderSheetHostProblem(source)).toBeNull();
});
