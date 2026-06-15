//
// DietPhaseHistoryView.swift
// LogYourBody
//
import SwiftUI
import Foundation
enum PhaseType: String, CaseIterable {
    case bulk = "Bulk"
    case cut = "Cut"
    case maintenance = "Maintenance"
}

struct DietPhaseHistoryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diet Phase History")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.appText)

                            Text("Track your bulk, cut, and maintenance phases")
                                .font(.system(size: 16))
                                .foregroundColor(.appTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                        emptyState
                            .padding(.horizontal, 20)
                            .padding(.top, 24)

                        // Bottom padding
                        Color.clear.frame(height: 100)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.appTextSecondary)

            VStack(spacing: 6) {
                Text("No phase history yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.appText)

                Text("Real bulk, cut, and maintenance phases will appear here once phase tracking is available.")
                    .font(.system(size: 14))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appBorder.opacity(0.1), lineWidth: 1)
        )
    }
}

// Temporary inline card view until DietPhaseCard is added to project
struct PhaseCardView: View {
    let phase: PhaseType
    let startDate: Date
    let endDate: Date
    let startWeight: Double
    let endWeight: Double
    let startBodyFat: Double?
    let endBodyFat: Double?
    let weightUnit: String

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
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let startYear = calendar.component(.year, from: startDate)
        let endYear = calendar.component(.year, from: endDate)

        // If dates span across years or if start date is from a previous year
        if startYear != endYear || startYear < currentYear {
            formatter.dateFormat = "MMM d, yyyy"
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        } else {
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .bulk: return Color.blue
        case .cut: return Color.orange
        case .maintenance: return Color.green
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .bulk: return "arrow.up.circle.fill"
        case .cut: return "arrow.down.circle.fill"
        case .maintenance: return "equal.circle.fill"
        }
    }

    private func bodyFatChangeColor(for change: Double) -> Color {
        change <= 0 ? .green : .red
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                // Left side - dates and phase info
                VStack(alignment: .leading, spacing: 8) {
                    // Date range
                    Text(dateRangeFormatted)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.appTextSecondary)

                    // Phase type with color indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(phaseColor)
                            .frame(width: 8, height: 8)
                        Text(phase.rawValue.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Spacer()

                // Right side - duration
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(duration)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.appText)
                    Text("weeks")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Divider
            Rectangle()
                .fill(Color.appBorder.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Metrics - simplified layout
            HStack(spacing: 20) {
                // Weight range on left
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weight")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.appTextTertiary)
                    Text("\(String(format: "%.0f", startWeight))–\(String(format: "%.0f", endWeight)) \(weightUnit)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                // Changes on right - big and bold
                HStack(spacing: 16) {
                    // Weight change
                    HStack(spacing: 4) {
                        Image(systemName: weightChange > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor((phase == .bulk ? weightChange > 0 : weightChange < 0) ? .green : .red)
                        Text(String(format: "%.1f", abs(weightChange)))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor((phase == .bulk ? weightChange > 0 : weightChange < 0) ? .green : .red)
                        Text(weightUnit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor((phase == .bulk ? weightChange > 0 : weightChange < 0) ? .green : .red)
                    }

                    // Body fat change if available
                    if let change = bodyFatChange {
                        HStack(spacing: 4) {
                            Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(bodyFatChangeColor(for: change))
                            Text(String(format: "%.1f", abs(change)))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(bodyFatChangeColor(for: change))
                            Text("%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(bodyFatChangeColor(for: change))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appBorder.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    DietPhaseHistoryView()
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
