import SwiftUI

struct DatedOutcomeStatsView: View {
    let stats: DatedOutcomeStats

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
            Text(stats.presentation.title)
                .font(.title2)
                .accessibilityIdentifier("dated_stats_status")
            if let target = stats.target {
                row("Your selected target", value: target, caption: stats.deadline ?? "", id: "target")
            }
            if let remaining = stats.remaining {
                Text(remaining)
                    .accessibilityIdentifier("dated_stats_remaining")
            }
            if let measurement = stats.measurement {
                row("Recorded value", value: measurement.text, caption: measurement.caption, id: "measurement")
            } else {
                row("Recorded value", value: "—", caption: "No comparable measurement", id: "measurement")
            }
            if let estimate = stats.estimate {
                row("Estimate", value: estimate.text, caption: estimate.caption, id: "estimate")
            }
            if let baseline = stats.baseline {
                row("Plan baseline", value: baseline.text, caption: baseline.caption, id: "baseline")
            }
            if let drift = stats.drift {
                row("Planner drift", value: drift.text, caption: drift.caption, id: "drift")
            }
            Text(LaunchPromiseCopy.framing)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dated_stats_\(stats.presentation.state.rawValue)")
    }

    private func row(_ title: String, value: String, caption: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline)
            Text(value).font(.title3.monospacedDigit())
            Text(caption).font(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dated_stats_\(id)")
    }
}
