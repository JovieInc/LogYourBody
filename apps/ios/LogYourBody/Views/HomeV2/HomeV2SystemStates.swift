//
// HomeV2SystemStates.swift
// LogYourBody
//
import Foundation
import SwiftUI

enum HomeV2SystemCopy {
    static let offline = "Offline. Showing what’s saved on this iPhone."
    static let healthOffTitle = "Apple Health is off"
    static let healthOffSubline = "Weight and steps aren’t syncing"
    static let logWeightManually = "Log weight manually"
    static let connectAppleHealth = "Connect Apple Health"
    static let loadingHistory = "Loading your history…"
    static let loading = "Loading…"
}

/// A status Home must never hide (Pencil H62RV, GNxb7, RuP46).
enum HomeV2SystemState: String, Equatable {
    case offline
    case healthOff
    case loading
}

enum HomeV2SystemStatePolicy {
    static let offlineFixtureArgument = "-lybUITestHomeV2OfflineFixture"
    static let healthOffFixtureArgument = "-lybUITestHomeV2HealthOffFixture"
    static let loadingFixtureArgument = "-lybUITestHomeV2LoadingFixture"
    /// Set once Apple Health has ever been authorized on this device, so "off"
    /// only ever means "was on".
    static let everAuthorizedKey = "homeV2HealthEverAuthorized"

    /// Loading wins, then offline, then Apple Health off. "Off" means sync is
    /// wanted, authorization was granted before and is missing now, and Apple
    /// Health data exists, so a manual-only person is never nagged.
    static func state(
        hasLoadedInitialData: Bool,
        isOnline: Bool,
        healthSyncEnabled: Bool,
        healthAuthorized: Bool,
        healthEverAuthorized: Bool,
        hasHealthData: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> HomeV2SystemState? {
        #if DEBUG
        if arguments.contains(loadingFixtureArgument) { return .loading }
        if arguments.contains(offlineFixtureArgument) { return .offline }
        if arguments.contains(healthOffFixtureArgument) { return .healthOff }
        #endif
        if !hasLoadedInitialData { return .loading }
        if !isOnline { return .offline }
        if healthSyncEnabled, healthEverAuthorized, !healthAuthorized, hasHealthData { return .healthOff }
        return nil
    }

    /// Remembers an authorization so a later revocation reads as "off".
    static func recordAuthorization(_ isAuthorized: Bool, defaults: UserDefaults = .standard) {
        guard isAuthorized else { return }
        defaults.set(true, forKey: everAuthorizedKey)
    }
}

/// 48pt banner under the header: the app is offline and says so.
struct HomeV2OfflineBanner: View {
    var body: some View {
        HStack(spacing: HomeV2Tokens.Space.row) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 14, weight: .medium))
            Text(HomeV2SystemCopy.offline)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(HomeV2Tokens.Colors.secondary)
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home_v2_offline_banner")
    }
}

/// 60pt status row: Apple Health sync is wanted but not authorized.
struct HomeV2HealthOffRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HomeV2SystemCopy.healthOffTitle)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            Text(HomeV2SystemCopy.healthOffSubline)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home_v2_health_off")
    }
}

/// One Home card. A real photo, an empty day, a load, a failed load and offline
/// all keep this frame. Copy and pixels change inside it.
enum HomeV2StagePresentation: Equatable, CaseIterable {
    case photo
    case noPhoto
    case loading
    case failedLoad
    case offline
}

enum HomeV2StageReservation {
    #if DEBUG
    static let photoLoadFailedFixtureArgument = "-lybUITestHomeV2PhotoLoadFailedFixture"
    #endif

    static func size(width: CGFloat, presentation: HomeV2StagePresentation) -> CGSize {
        let safeWidth = width.isFinite ? max(width, 0) : 0
        let height: CGFloat
        switch presentation {
        case .photo, .noPhoto, .loading, .failedLoad, .offline:
            height = safeWidth / HomeV2Tokens.photoAspectRatio
        }
        return CGSize(width: safeWidth, height: height.isFinite ? height : 0)
    }
}

extension View {
    func homeV2ReservedStage(width: CGFloat, presentation: HomeV2StagePresentation) -> some View {
        let stage = HomeV2StageReservation.size(width: width, presentation: presentation)
        return frame(width: stage.width, height: stage.height)
    }
}

/// Home while the first load runs (Pencil RuP46): the same 4:5 card as a photo,
/// an honest line, and a disabled dock.
struct HomeV2LoadingHome: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        HomeV2Tokens.Colors.card
                        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.row) {
                            skeleton(width: min(150, geometry.size.width * 0.4), height: 56)
                            skeleton(width: min(190, geometry.size.width * 0.5), height: 14)
                            skeleton(width: min(150, geometry.size.width * 0.4), height: 12)
                        }
                        .padding(HomeV2Tokens.Space.margin)
                    }
                    .homeV2ReservedStage(width: geometry.size.width, presentation: .loading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(HomeV2SystemCopy.loadingHistory)
                    .accessibilityIdentifier("home_v2_editorial_card")

                    Text(HomeV2SystemCopy.loadingHistory)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .padding(.horizontal, HomeV2Tokens.Space.margin)
                        .padding(.top, HomeV2Tokens.Space.margin)
                        .accessibilityIdentifier("home_v2_loading")
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("home_v2_content_scroll")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HomeV2PrimaryButton(
                title: HomeV2SystemCopy.loading,
                isEnabled: false,
                identifier: "home_v2_loading_dock",
                action: {}
            )
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.vertical, HomeV2Tokens.Space.tight)
            .background(HomeV2Tokens.Colors.shell)
        }
        .accessibilityElement(children: .contain)
    }

    private func skeleton(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: HomeV2Tokens.Space.tight, style: .continuous)
            .fill(HomeV2Tokens.Colors.elevated)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
