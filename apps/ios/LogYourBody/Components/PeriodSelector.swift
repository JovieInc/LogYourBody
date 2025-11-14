//
// PeriodSelector.swift
// LogYourBody
//
// Reusable period selector for metric detail views
// Matches Apple Health's time range selector design
//

import SwiftUI

// MARK: - Time Period Enum

enum TimePeriod: String, CaseIterable, Identifiable {
    case day = "D"
    case week = "W"
    case month = "M"
    case sixMonths = "6M"
    case year = "Y"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 180
        case .year: return 365
        }
    }

    var displayName: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .sixMonths: return "6 Months"
        case .year: return "Year"
        }
    }
}

// MARK: - Period Selector Component

struct PeriodSelector: View {
    @Binding var selectedPeriod: TimePeriod

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TimePeriod.allCases) { period in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedPeriod = period
                    }
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedPeriod == period ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedPeriod == period ?
                                Color.white.opacity(0.9) :
                                Color.clear
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // On dark background
        PeriodSelector(selectedPeriod: .constant(.week))
            .padding(20)
            .background(Color.black)

        // Changing selection
        PeriodSelector(selectedPeriod: .constant(.month))
            .padding(20)
            .background(Color.black)

        // Year selected
        PeriodSelector(selectedPeriod: .constant(.year))
            .padding(20)
            .background(Color.black)
    }
}
