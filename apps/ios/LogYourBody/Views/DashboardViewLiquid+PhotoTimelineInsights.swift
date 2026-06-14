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
                        .foregroundColor(Color.liquidTextPrimary)

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
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = insight.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                            .foregroundColor(Color.liquidTextPrimary)

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
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(summary.actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo_timeline_hud_glp1_weekly_checkin")
        .accessibilityLabel("\(summary.title). \(summary.message). \(summary.actionTitle)")
    }

    var hudStatsAction: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedPhotoTimelineRootPage = .analytics
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.metricAccent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stats")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary)

                    Text("Charts, sources, and history")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.58))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.42))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo_timeline_hud_stats_button")
        .accessibilityLabel("Open stats")
    }

    var isPhaseInsightEnabled: Bool {
        _ = featureGateRefreshToken

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestPhaseInsightFixture") {
            return true
        }
        #endif

        return PhaseInsightPolicy.shouldShowPhaseInsight(
            gateEnabled: AnalyticsService.shared.isFeatureEnabled(
                flagKey: Constants.phaseInsightFlagKey
            )
        )
    }

    var isGlp1WeeklyCheckInEnabled: Bool {
        _ = featureGateRefreshToken

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") {
            return true
        }
        #endif

        return Glp1WeeklyCheckInPolicy.shouldShowWeeklyCheckIn(
            gateEnabled: AnalyticsService.shared.isFeatureEnabled(
                flagKey: Constants.glp1WeeklyCheckInFlagKey
            )
        )
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
            return Color.metricAccentBodyFat
        case .maintaining:
            return Color.metricAccent
        case .gaining:
            return Color.metricAccentWeight
        case .insufficientData:
            return Color.metricTextTertiary
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
            return Color.metricAccent
        case .due:
            return Color.metricAccentWeight
        case .logged:
            return Color.metricAccentSteps
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

    func photoTimelinePresenceColor(for presence: MetricPresence) -> Color {
        switch presence {
        case .present:
            return Color.metricChartLine
        case .interpolated:
            return Color.metricAccentBodyFat
        case .lastKnown:
            return Color.metricAccentFFMI
        case .missing:
            return Color.metricTextTertiary
        }
    }
}
