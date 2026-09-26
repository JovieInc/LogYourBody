//
// HomeV2LogWeightSheet.swift
// LogYourBody
//
import SwiftUI

/// Log weight (Pencil L1/L1a): the number with −/+ steps or typing, optional
/// details behind one disclosure, one Save action. Persistence stays with the
/// caller; the sheet reports success or shows why it could not save.
struct HomeV2LogWeightSheet: View {
    let unit: String
    let initialValue: Double
    let dateText: String
    let onSave: (_ value: Double, _ bodyFat: Double?) async -> Bool
    let onAddPhoto: (_ pose: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var valueText: String
    @State private var bodyFatText: String
    @State private var showsDetails = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var detent: PresentationDetent = .medium
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight
        case bodyFat
    }

    init(
        unit: String,
        initialValue: Double,
        initialBodyFat: Double?,
        dateText: String,
        onSave: @escaping (_ value: Double, _ bodyFat: Double?) async -> Bool,
        onAddPhoto: @escaping (_ pose: String) -> Void
    ) {
        self.unit = unit
        self.initialValue = initialValue
        self.dateText = dateText
        self.onSave = onSave
        self.onAddPhoto = onAddPhoto
        _valueText = State(initialValue: HomeV2WeightStepPolicy.text(initialValue))
        _bodyFatText = State(initialValue: initialBodyFat.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            stepper
                .padding(.top, HomeV2Tokens.Space.margin)

            if let errorText {
                Text(errorText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.red)
                    .padding(.top, HomeV2Tokens.Space.tight)
                    .accessibilityIdentifier("home_v2_log_sheet_error")
            }

            if showsDetails {
                details
                    .padding(.top, HomeV2Tokens.Space.compact)
            } else {
                detailsDisclosure
                    .padding(.top, HomeV2Tokens.Space.compact)
            }

            Spacer(minLength: HomeV2Tokens.Space.compact)

            HomeV2PrimaryButton(
                title: HomeV2Copy.saveWeight,
                isEnabled: !isSaving,
                identifier: "home_v2_log_sheet_save",
                action: save
            )
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.top, HomeV2Tokens.Space.margin)
        .padding(.bottom, HomeV2Tokens.Space.tight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HomeV2Tokens.Colors.elevated)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(HomeV2Tokens.Colors.elevated)
        .onChange(of: showsDetails) { _, shows in
            if shows { detent = .large }
        }
        .onChange(of: focusedField) { previous, current in
            if previous == .weight, current != .weight { commitTypedWeight() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: HomeV2Tokens.Space.tight) {
            Text(HomeV2Copy.logSheetTitle)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .bold, relativeTo: .title2)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home_v2_log_sheet")

            Spacer(minLength: HomeV2Tokens.Space.tight)

            HStack(spacing: HomeV2Tokens.Space.tight) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                Text(dateText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .padding(.horizontal, HomeV2Tokens.Space.row)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .background(HomeV2Tokens.Colors.card, in: Capsule())
            .accessibilityIdentifier("home_v2_log_sheet_date")
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", direction: -1, identifier: "home_v2_log_sheet_minus")

            Spacer(minLength: HomeV2Tokens.Space.tight)

            VStack(spacing: 0) {
                TextField("", text: $valueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetValue, weight: .semibold, relativeTo: .largeTitle)
                    .kerning(-1.5)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .focused($focusedField, equals: .weight)
                    .accessibilityLabel("Weight")
                    .accessibilityIdentifier("home_v2_log_sheet_value")

                Text(unit)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.muted)
            }

            Spacer(minLength: HomeV2Tokens.Space.tight)

            stepButton(systemImage: "plus", direction: 1, identifier: "home_v2_log_sheet_plus")
        }
    }

    private func stepButton(systemImage: String, direction: Int, identifier: String) -> some View {
        Button {
            step(direction)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? "Decrease weight" : "Increase weight")
        .accessibilityIdentifier(identifier)
    }

    private var detailsDisclosure: some View {
        Button {
            showsDetails = true
        } label: {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2Copy.addDetails)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
            }
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_v2_log_sheet_details")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2Copy.bodyFat)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)

                Spacer(minLength: HomeV2Tokens.Space.tight)

                TextField(HomeV2Copy.bodyFatPlaceholder, text: $bodyFatText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: 72)
                    .focused($focusedField, equals: .bodyFat)
                    .accessibilityLabel("Body fat percent")
                    .accessibilityIdentifier("home_v2_log_sheet_body_fat")

                Text("%")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
            .frame(minHeight: HomeV2Tokens.rowHeight)
            .overlay(alignment: .bottom) { HomeV2Hairline() }

            HStack(spacing: HomeV2Tokens.Space.tight) {
                ForEach(HomeV2Copy.poses, id: \.self) { pose in
                    photoSlot(pose)
                }
            }

            Text(HomeV2Copy.ghostHint)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func photoSlot(_ pose: String) -> some View {
        Button {
            onAddPhoto(pose)
        } label: {
            VStack(spacing: HomeV2Tokens.Space.tight) {
                Image(systemName: "camera")
                    .font(.system(size: 20, weight: .medium))
                Text(pose)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
            }
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .frame(maxWidth: .infinity, minHeight: HomeV2Tokens.photoSlotHeight)
            .background(
                HomeV2Tokens.Colors.card,
                in: RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(pose) photo")
        .accessibilityIdentifier("home_v2_log_sheet_photo_\(pose.lowercased())")
    }

    private func step(_ direction: Int) {
        let current = HomeV2WeightStepPolicy.parse(valueText) ?? initialValue
        valueText = HomeV2WeightStepPolicy.text(HomeV2WeightStepPolicy.stepped(current, by: direction, unit: unit))
        errorText = nil
        HapticManager.shared.selection()
    }

    private func commitTypedWeight() {
        guard let typed = HomeV2WeightStepPolicy.parse(valueText) else { return }
        valueText = HomeV2WeightStepPolicy.text(HomeV2WeightStepPolicy.clamped(typed, unit: unit))
    }

    private func save() {
        focusedField = nil
        guard let value = HomeV2WeightStepPolicy.parse(valueText),
              HomeV2WeightStepPolicy.range(unit: unit).contains(value) else {
            errorText = HomeV2Copy.weightRangeError(unit: unit)
            return
        }

        var bodyFat: Double?
        if !bodyFatText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = HomeV2WeightStepPolicy.parse(bodyFatText),
                  HomeV2WeightStepPolicy.bodyFatRange.contains(parsed) else {
                errorText = HomeV2Copy.bodyFatRangeError
                return
            }
            bodyFat = parsed
        }

        errorText = nil
        isSaving = true
        Task { @MainActor in
            let saved = await onSave(value, bodyFat)
            isSaving = false
            if saved {
                dismiss()
            } else {
                errorText = HomeV2Copy.saveFailed
            }
        }
    }
}
