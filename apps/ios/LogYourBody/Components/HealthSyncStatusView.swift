import SwiftUI

struct HealthSyncStatusView: View {
    let state: HealthSyncState
    let lastSync: Date?
    let receipt: HealthWeightReceipt?
    let unit: String
    let onRecentReadings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            Button(action: onRecentReadings) {
                Text(HealthSyncPresentationPolicy.caption(state: state, lastSync: lastSync, locale: locale, timeZone: timeZone))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens recent Apple Health readings")
            .accessibilityIdentifier("health_sync_caption")

            if let receipt {
                Button(action: onRecentReadings) {
                    HStack(alignment: .firstTextBaseline, spacing: HomeV2Tokens.Space.tight) {
                        Text(receipt.text(unit: unit, locale: locale, timeZone: timeZone))
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens recent readings to edit or exclude a weight")
                .accessibilityIdentifier("health_weight_receipt")
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: JovieTokens.subtleDuration), value: receipt?.id)
    }
}
