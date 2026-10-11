//
// HomeV2PrimaryButton.swift
// LogYourBody
//
import SwiftUI

/// The one high-emphasis action per screen (Pencil "Primary action"): a
/// 52pt pill, light fill, dark ink. Consumers supply the label and identifier.
struct HomeV2PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(HomeV2Tokens.Colors.ctaInk)
            .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
            .background(HomeV2Tokens.Colors.ctaFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityIdentifier(identifier)
    }
}

/// The action dock at the bottom of a Home state: the primary button on the
/// canvas with the design's margins, above the home indicator.
struct HomeV2Dock: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        HomeV2PrimaryButton(title: title, identifier: identifier, action: action)
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.top, HomeV2Tokens.Space.tight)
            .padding(.bottom, HomeV2Tokens.Space.tight)
    }
}

/// A quiet text row with a trailing chevron: the design's disclosure to a
/// destination that exists ("View progress", "Connect Apple Health instead").
struct HomeV2DisclosureLink: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
            }
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// H0: the first check-in. One sentence, one quiet alternative, one action.
struct HomeV2DayZero: View {
    let onConnectHealth: () -> Void
    let onLogWeight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
                Text(HomeV2Copy.firstCheckInTitle)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.heroPhoto, weight: .bold, relativeTo: .largeTitle)
                    .kerning(-1)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home_v2_day_zero")

                Text(HomeV2Copy.firstCheckInBody)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HomeV2DisclosureLink(
                    title: HomeV2Copy.connectHealthInstead,
                    identifier: "home_v2_connect_health",
                    action: onConnectHealth
                )
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.top, HomeV2Tokens.Space.dayZeroTop)

            Spacer(minLength: 0)

            HomeV2Dock(title: HomeV2Copy.logWeight, identifier: "home_v2_log_weight", action: onLogWeight)
        }
    }
}
