//
//  DashboardViewLiquid+HomeTimelineControls.swift
//  LogYourBody
//

import SwiftUI
import UIKit

extension DashboardViewLiquid {
    var selectedDefaultHomeMode: DefaultHomeMode {
        DefaultHomeMode(storedValue: defaultHomeModeRawValue)
    }

    var selectedHomeTimelineMode: TimelineMode {
        selectedDefaultHomeMode.timelineMode
    }

    var homeTimelineModeBinding: Binding<TimelineMode> {
        Binding(
            get: { selectedHomeTimelineMode },
            set: { newValue in
                defaultHomeModeRawValue = DefaultHomeMode(timelineMode: newValue).rawValue
            }
        )
    }

    var homeModeSwitch: some View {
        JovieSegmentedControl(
            selection: Binding(
                get: { selectedDefaultHomeMode },
                set: { defaultHomeModeRawValue = $0.rawValue }
            ),
            items: Array(DefaultHomeMode.allCases),
            title: { $0.title },
            systemImage: { $0.iconName },
            accessibilityLabel: { $0.title },
            accessibilityHint: { "Shows the \($0.title.lowercased()) home timeline" },
            accessibilityIdentifier: { "home_mode_\($0.rawValue)_button" },
            selectedTint: theme.colors.text,
            selectedForeground: theme.colors.background,
            unselectedForeground: theme.colors.textSecondary,
            onSelection: { _ in HapticManager.shared.selection() }
        )
        .systemBGlassSurface(
            cornerRadius: theme.radius.full,
            tint: theme.colors.text,
            tintOpacity: 0.025,
            borderColor: theme.colors.border,
            borderOpacity: 0.85
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_mode_switch")
    }

    func homeTimelineHero(metric: BodyMetrics) -> some View {
        let bodyScore = bodyScoreText()

        return DashboardHomeTimelineHero(
            metric: metric,
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            displayMode: $photoDisplayMode,
            homeMode: selectedDefaultHomeMode,
            dateText: formatHUDDate(metric.date),
            gender: authManager.currentUser?.profile?.gender,
            bodyScoreText: bodyScore.scoreText,
            bodyScoreTagline: bodyScore.tagline,
            bodyScoreDeltaText: heroBodyScoreDeltaText(),
            weightValue: heroWeightValue(),
            weightCaption: heroWeightCaption(),
            bodyFatValue: heroBodyFatValue(),
            bodyFatCaption: heroBodyFatCaption(),
            ffmiValue: heroFFMIValue(),
            ffmiCaption: heroFFMICaption(),
            onTapBodyScore: bodyScore.score > 0 ? {
                selectedMetricType = .bodyScore
                isMetricDetailActive = true
            } : nil,
            onTapWeight: {
                selectedMetricType = .weight
                isMetricDetailActive = true
            },
            onTapBodyFat: {
                selectedMetricType = .bodyFat
                isMetricDetailActive = true
            },
            onTapFFMI: {
                selectedMetricType = .ffmi
                isMetricDetailActive = true
            },
            onShareBodyScore: makeBodyScoreShareAction(metric: metric, score: bodyScore.score)
        )
    }

    func makeBodyScoreShareAction(metric: BodyMetrics? = nil, score: Int? = nil) -> (() -> Void)? {
        if let score, score <= 0 { return nil }
        guard let initialPayload = makeBodyScoreSharePayload(metric: metric) else { return nil }

        return {
            let presentationID = UUID()
            bodyScoreSharePresentationID = presentationID
            bodyScoreSharePayload = initialPayload

            Task { @MainActor in
                guard let resolvedPayload = await makeBodyScoreSharePayloadResolvingPhoto(metric: metric),
                      resolvedPayload.photoImage != nil,
                      bodyScoreSharePresentationID == presentationID else {
                    return
                }

                bodyScoreSharePayload = resolvedPayload
            }
        }
    }

    @MainActor
    func makeBodyScoreSharePayloadResolvingPhoto(metric: BodyMetrics? = nil) async -> BodyScoreSharePayload? {
        let selectedMetric = metric ?? currentMetric
        let photoImage = await sharePhotoImageResolvingCache(for: selectedMetric)
        return makeBodyScoreSharePayload(metric: selectedMetric, photoImageOverride: photoImage)
    }

    private func sharePhotoImageResolvingCache(for metric: BodyMetrics?) async -> UIImage? {
        guard selectedDefaultHomeMode == .photo,
              let photoUrl = metric?.photoUrl,
              !photoUrl.isEmpty else {
            return nil
        }

        return await OptimizedProgressPhotoView.resolvedImage(for: photoUrl)
    }
}
