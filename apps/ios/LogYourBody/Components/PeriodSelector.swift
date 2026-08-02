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

// MARK: - Shared Liquid Glass Segmented Control

/// A compact, equal-width segmented control for narrow iPhone layouts.
///
/// iOS 26 gets the native Liquid Glass treatment while earlier OS versions use
/// the app's existing material fallback. Keeping both selectors on this
/// primitive prevents mobile spacing and accessibility behavior from drifting
/// between screens.
struct JovieSegmentedControl<Selection: Hashable>: View {
    @Binding var selection: Selection

    let items: [Selection]
    let title: (Selection) -> String
    let systemImage: (Selection) -> String?
    let accessibilityLabel: (Selection) -> String
    let accessibilityHint: (Selection) -> String
    let accessibilityIdentifier: (Selection) -> String
    let selectedTint: Color
    let selectedForeground: Color
    let unselectedForeground: Color
    let onSelection: ((Selection) -> Void)?

    init(
        selection: Binding<Selection>,
        items: [Selection],
        title: @escaping (Selection) -> String,
        systemImage: @escaping (Selection) -> String? = { _ in nil },
        accessibilityLabel: @escaping (Selection) -> String,
        accessibilityHint: @escaping (Selection) -> String,
        accessibilityIdentifier: @escaping (Selection) -> String,
        selectedTint: Color,
        selectedForeground: Color,
        unselectedForeground: Color,
        onSelection: ((Selection) -> Void)? = nil
    ) {
        _selection = selection
        self.items = items
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.selectedTint = selectedTint
        self.selectedForeground = selectedForeground
        self.unselectedForeground = unselectedForeground
        self.onSelection = onSelection
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(items, id: \.self) { item in
                            nativeSegment(for: item)
                        }
                    }
                    .padding(4)
                }
            } else {
                fallbackSegments
            }
        }
        .accessibilityElement(children: .contain)
    }

    @available(iOS 26.0, *)
    private func nativeSegment(for item: Selection) -> some View {
        segmentButton(for: item)
            // Apply glass after sizing and content modifiers so the material
            // follows the actual 44pt hit target rather than clipping it.
            .glassEffect(
                selectedGlass(for: item),
                in: Capsule(style: .continuous)
            )
    }

    @available(iOS 26.0, *)
    private func selectedGlass(for item: Selection) -> Glass {
        if selection == item {
            return .regular
                .tint(selectedTint.opacity(0.2))
                .interactive()
        }

        return .regular.interactive()
    }

    private var fallbackSegments: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                fallbackSegment(for: item)
            }
        }
        .padding(4)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.controlRadius,
            tint: selectedTint,
            tintOpacity: 0.025,
            borderColor: Color.white.opacity(0.12),
            borderOpacity: 1
        )
    }

    private func fallbackSegment(for item: Selection) -> some View {
        segmentButton(for: item)
            .background(
                Capsule(style: .continuous)
                    .fill(selection == item ? selectedTint : Color.clear)
            )
    }

    private func segmentButton(for item: Selection) -> some View {
        let isSelected = selection == item

        return Button {
            withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) {
                selection = item
            }
            onSelection?(item)
        } label: {
            Group {
                if let systemImageName = systemImage(item) {
                    Label(title(item), systemImage: systemImageName)
                } else {
                    Text(title(item))
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: JovieTokens.compactControlHeight)
            .foregroundStyle(isSelected ? selectedForeground : unselectedForeground)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(item))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(accessibilityHint(item))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(accessibilityIdentifier(item))
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
                        .foregroundColor(
                            selectedPeriod == period ? Color.metricTextPrimary : Color(hex: "#C7CBD3")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPeriod == period ? Color.metricAccent : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            selectedPeriod == period ? Color.clear : Color(hex: "#2A2E36"),
                                            lineWidth: selectedPeriod == period ? 0 : 1
                                        )
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
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
