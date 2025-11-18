//
// DietPhaseCard.swift
// LogYourBody
//
import SwiftUI
import Foundation

struct DietPhaseCard: View {
    let phaseType: PhaseType
    let startDate: Date
    let endDate: Date
    let startWeight: Double
    let endWeight: Double
    let startBodyFat: Double?
    let endBodyFat: Double?
    let weightUnit: String

    enum PhaseType: String, CaseIterable {
        case bulk = "Bulk"
        case cut = "Cut"
        case maintenance = "Maintenance"

        var icon: String {
            switch self {
            case .bulk: return "arrow.up.circle.fill"
            case .cut: return "arrow.down.circle.fill"
            case .maintenance: return "equal.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .bulk: return Color.blue
            case .cut: return Color.orange
            case .maintenance: return Color.green
            }
        }
    }

    // Computed properties
    private var duration: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekOfYear], from: startDate, to: endDate)
        return max(1, components.weekOfYear ?? 1)
    }

    private var weightChange: Double {
        endWeight - startWeight
    }

    private var weightChangeFormatted: String {
        let change = weightChange
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change)) \(weightUnit)"
    }

    private var bodyFatChange: Double? {
        guard let start = startBodyFat, let end = endBodyFat else { return nil }
        return end - start
    }

    private var bodyFatChangeFormatted: String? {
        guard let change = bodyFatChange else { return nil }
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change))%"
    }

    private var dateRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with phase type and duration
            HStack {
                // Phase type badge
                HStack(spacing: 6) {
                    Image(systemName: phaseType.icon)
                        .font(.system(size: 14, weight: .medium))
                    Text(phaseType.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(phaseType.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(phaseType.color.opacity(0.15))
                )

                Spacer()

                // Duration
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(duration)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.appText)
                    Text("weeks")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Date range
            Text(dateRangeFormatted)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.appTextSecondary)
                .padding(.bottom, 16)

            // Divider
            Rectangle()
                .fill(Color.appBorder.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Metrics grid
            HStack(spacing: 0) {
                // Weight column
                VStack(spacing: 12) {
                    // Starting weight
                    MetricItem(
                        label: "Start",
                        value: String(format: "%.1f", startWeight),
                        unit: weightUnit,
                        icon: "scalemass"
                    )

                    // Ending weight
                    MetricItem(
                        label: "End",
                        value: String(format: "%.1f", endWeight),
                        unit: weightUnit,
                        icon: "scalemass"
                    )
                }
                .frame(maxWidth: .infinity)

                // Vertical divider
                Rectangle()
                    .fill(Color.appBorder.opacity(0.3))
                    .frame(width: 1)
                    .padding(.vertical, 16)

                // Changes column
                VStack(spacing: 12) {
                    // Weight change
                    ChangeItem(
                        label: "Weight",
                        value: weightChangeFormatted,
                        isPositive: phaseType == .bulk ? weightChange > 0 : weightChange < 0
                    )

                    // Body fat change
                    if let bfChange = bodyFatChangeFormatted {
                        ChangeItem(
                            label: "Body Fat",
                            value: bfChange,
                            isPositive: phaseType == .cut ? (bodyFatChange ?? 0) < 0 : (bodyFatChange ?? 0) < 0
                        )
                    } else {
                        ChangeItem(
                            label: "Body Fat",
                            value: "—",
                            isPositive: nil
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
        }
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appBorder.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Subcomponents

private struct MetricItem: View {
    let label: String
    let value: String
    let unit: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.appTextTertiary)

            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appTextSecondary)

                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.appText)

                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

private struct ChangeItem: View {
    let label: String
    let value: String
    let isPositive: Bool?

    private var changeColor: Color {
        guard let isPositive = isPositive else { return .appTextSecondary }
        return isPositive ? .green : .red
    }

    private var changeIcon: String {
        guard let isPositive = isPositive else { return "" }
        return isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.appTextTertiary)

            HStack(spacing: 4) {
                if isPositive != nil {
                    Image(systemName: changeIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(changeColor.opacity(0.8))
                }

                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(isPositive != nil ? changeColor : .appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

struct DietPhaseCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Bulk phase example
            DietPhaseCard(
                phaseType: .bulk,
                startDate: Date().addingTimeInterval(-60 * 60 * 24 * 56), // 8 weeks ago
                endDate: Date(),
                startWeight: 180,
                endWeight: 188,
                startBodyFat: 15.0,
                endBodyFat: 16.5,
                weightUnit: "lbs"
            )

            // Cut phase example
            DietPhaseCard(
                phaseType: .cut,
                startDate: Date().addingTimeInterval(-60 * 60 * 24 * 84), // 12 weeks ago
                endDate: Date().addingTimeInterval(-60 * 60 * 24 * 56), // 8 weeks ago
                startWeight: 195,
                endWeight: 180,
                startBodyFat: 20.0,
                endBodyFat: 15.0,
                weightUnit: "lbs"
            )

            // Maintenance phase example (no BF data)
            DietPhaseCard(
                phaseType: .maintenance,
                startDate: Date().addingTimeInterval(-60 * 60 * 24 * 28), // 4 weeks ago
                endDate: Date(),
                startWeight: 180,
                endWeight: 181,
                startBodyFat: nil,
                endBodyFat: nil,
                weightUnit: "lbs"
            )
        }
        .padding()
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
    }
}
