//
//  DashboardViewLiquid+HomeTimelineControls.swift
//  LogYourBody
//

import SwiftUI

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
        HStack(spacing: 4) {
            ForEach(DefaultHomeMode.allCases) { mode in
                homeModeButton(mode)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_mode_switch")
    }

    func homeModeButton(_ mode: DefaultHomeMode) -> some View {
        let isSelected = selectedDefaultHomeMode == mode

        return Button {
            defaultHomeModeRawValue = mode.rawValue
            HapticManager.shared.selection()
        } label: {
            Label(mode.title, systemImage: mode.iconName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundColor(isSelected ? .black : Color.white.opacity(0.72))
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_mode_\(mode.rawValue)_button")
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

        return {
            if let payload = makeBodyScoreSharePayload(metric: metric) {
                bodyScoreSharePayload = payload
            }
        }
    }
}
