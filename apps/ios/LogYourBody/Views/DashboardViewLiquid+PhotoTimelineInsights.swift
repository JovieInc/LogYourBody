import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Photo Timeline Insights

    var hudPhaseInsight: some View {
        let insight = PhaseInsightPolicy.insight(for: bodyMetrics)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: phaseInsightIcon(for: insight.kind))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(phaseInsightColor(for: insight.kind))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(phaseInsightColor(for: insight.kind).opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(insight.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.colors.text)

                    if let delta = insight.weightDeltaPercentPerWeek {
                        Text(formatPhaseInsightDelta(delta))
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(phaseInsightColor(for: insight.kind))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(phaseInsightColor(for: insight.kind).opacity(0.14))
                            )
                    }
                }

                Text(insight.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = insight.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .systemBGlassSurface(
            cornerRadius: theme.radius.card,
            tint: theme.colors.text,
            tintOpacity: 0.025,
            borderColor: theme.colors.border,
            borderOpacity: 0.85
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photo_timeline_hud_phase_insight")
        .accessibilityLabel(phaseInsightAccessibilityLabel(for: insight))
    }

    var hudGlp1WeeklyCheckIn: some View {
        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: glp1Medications,
            doseLogs: glp1DoseLogs
        )

        return Button {
            presentAddEntrySheet(initialTab: 3, includesGlp1Entry: true)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "syringe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(glp1WeeklyCheckInColor(for: summary.status))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(glp1WeeklyCheckInColor(for: summary.status).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(summary.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.colors.text)

                        if let latestDoseText = summary.latestDoseText {
                            Text(latestDoseText)
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(glp1WeeklyCheckInColor(for: summary.status))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(glp1WeeklyCheckInColor(for: summary.status).opacity(0.14))
                                )
                        }
                    }

                    Text(summary.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(summary.actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.colors.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.colors.text))
            }
            .padding(14)
            .systemBGlassSurface(
                cornerRadius: theme.radius.card,
                tint: theme.colors.text,
                tintOpacity: 0.025,
                borderColor: theme.colors.border,
                borderOpacity: 0.85
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo_timeline_hud_glp1_weekly_checkin")
        .accessibilityLabel("\(summary.title). \(summary.message). \(summary.actionTitle)")
    }

    var isPhaseInsightEnabled: Bool {
        _ = featureGateRefreshToken

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestPhaseInsightFixture") {
            return true
        }
        #endif

        return PhaseInsightPolicy.shouldShowPhaseInsight()
    }

    var isGlp1WeeklyCheckInEnabled: Bool {
        _ = featureGateRefreshToken

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") {
            return true
        }
        #endif

        return Glp1WeeklyCheckInPolicy.shouldShowWeeklyCheckIn()
    }

    func loadGlp1WeeklyCheckInDataIfNeeded() {
        guard isGlp1WeeklyCheckInEnabled else { return }

        Task {
            await loadGlp1WeeklyCheckInData()
        }
    }

    func presentAddEntrySheet(initialTab: Int = 0, includesGlp1Entry: Bool = false) {
        addEntryInitialTab = initialTab
        addEntryIncludesGlp1Entry = includesGlp1Entry
        showAddEntrySheet = true
    }

    func phaseInsightIcon(for kind: PhaseInsightKind) -> String {
        switch kind {
        case .cutting:
            return "chart.line.downtrend.xyaxis"
        case .maintaining:
            return "equal.circle.fill"
        case .gaining:
            return "chart.line.uptrend.xyaxis"
        case .insufficientData:
            return "clock.badge.questionmark.fill"
        }
    }

    func phaseInsightColor(for kind: PhaseInsightKind) -> Color {
        switch kind {
        case .cutting:
            return theme.colors.accentPink
        case .maintaining:
            return theme.colors.primary
        case .gaining:
            return theme.colors.accentViolet
        case .insufficientData:
            return theme.colors.textTertiary
        }
    }

    func phaseInsightAccessibilityLabel(for insight: PhaseInsight) -> String {
        [
            insight.title,
            insight.message,
            insight.detail
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    func glp1WeeklyCheckInColor(for status: Glp1WeeklyCheckInStatus) -> Color {
        switch status {
        case .setup:
            return theme.colors.primary
        case .due:
            return theme.colors.accentViolet
        case .logged:
            return theme.colors.accentOrange
        }
    }

    func formatPhaseInsightDelta(_ value: Double) -> String {
        String(format: "%+.1f%%/wk", value)
    }

    func photoTimelinePresenceLabel(for presence: MetricPresence) -> String {
        switch presence {
        case .present:
            return "Measured"
        case .interpolated:
            return "Interpolated"
        case .lastKnown:
            return "Last known"
        case .missing:
            return "Missing"
        }
    }
}
