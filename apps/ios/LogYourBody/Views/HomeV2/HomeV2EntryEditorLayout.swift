import SwiftUI

enum HomeV2EntryEditorField: Hashable {
    case weight
    case bodyFat
}

/// Presentation only. The sheet retains draft ownership, validation, and record-scoped writes.
struct HomeV2EntryEditorLayout: View {
    let unit: String
    let dateText: String
    let initialWeightIsMissing: Bool
    let existingPhotoURL: String?
    let isSaving: Bool
    let errorText: String?
    @Binding var valueText: String
    @Binding var bodyFatText: String
    var focusedField: FocusState<HomeV2EntryEditorField?>.Binding
    let onSave: () -> Void
    let onDelete: (() -> Void)?
    let onAddPhoto: () -> Void
    let onClose: () -> Void
    let onStep: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var saveRequestID = 0

    private var isFocusedAccessibleEditor: Bool {
        dynamicTypeSize.isAccessibilitySize && focusedField.wrappedValue != nil
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header.id("entryHeader")
                        primaryBodyFat
                            .id(HomeV2EntryEditorField.bodyFat)
                            .padding(.top, isFocusedAccessibleEditor ? 0 : HomeV2Tokens.Space.margin)
                        primaryValidationSlot.id("entryValidation")
                        supportingWeight.id(HomeV2EntryEditorField.weight)
                        progressPhotoAction.padding(.top, HomeV2Tokens.Space.compact)
                    }
                    .padding(.horizontal, HomeV2Tokens.Space.margin)
                    .padding(.top, HomeV2Tokens.Space.margin)
                    .padding(.bottom, HomeV2Tokens.Space.compact)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("home_v2_edit_content_scroll")
                .clipped()
                .onChange(of: focusedField.wrappedValue) { _, _ in
                    revealFocusedEntry(using: proxy, viewportSize: viewport.size)
                }
                .onChange(of: viewport.size) { _, size in
                    revealFocusedEntry(using: proxy, viewportSize: size)
                }
                .onChange(of: errorText) { _, _ in
                    revealValidation(using: proxy)
                }
                .onChange(of: saveRequestID) { _, _ in
                    revealValidation(using: proxy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(HomeV2Tokens.Colors.canvas)
        .disabled(isSaving)
    }

    private func revealFocusedEntry(using proxy: ScrollViewProxy, viewportSize: CGSize) {
        guard dynamicTypeSize.isAccessibilitySize,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else { return }
        if let field = focusedField.wrappedValue {
            // Scroll the existing native field, preserving its draft, selection, and caret.
            proxy.scrollTo(field, anchor: .center)
        } else if errorText != nil {
            revealValidation(using: proxy)
        } else {
            // Restore the record context after Done instead of leaving its date half clipped.
            proxy.scrollTo("entryHeader", anchor: .top)
        }
    }

    private func revealValidation(using proxy: ScrollViewProxy) {
        guard dynamicTypeSize.isAccessibilitySize, errorText != nil else { return }
        proxy.scrollTo("entryValidation", anchor: .center)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
            HStack(alignment: .top, spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2ContextCopy.editEntry)
                    .font(HomeV2Tokens.Editor.display(size: 30, weight: .light, relativeTo: .title))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home_v2_log_sheet")
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Edit entry")
                .accessibilityIdentifier("home_v2_edit_close")
            }
            primaryDate
        }
    }

    private var actions: some View {
        VStack(spacing: HomeV2Tokens.Space.tight) {
            if focusedField.wrappedValue != nil {
                Button { focusedField.wrappedValue = nil } label: {
                    Text("Done editing")
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_v2_edit_done_editing")
            }
            if !isFocusedAccessibleEditor {
                Button {
                    onSave()
                    saveRequestID += 1
                } label: {
                    Text(HomeV2ContextCopy.saveChanges)
                        .scaledSystemFont(size: 16, weight: .semibold, relativeTo: .headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, HomeV2Tokens.Space.row)
                        .padding(.vertical, HomeV2Tokens.Space.tight)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(HomeV2Tokens.Colors.ctaInk)
                        .background(HomeV2Tokens.Colors.ctaFill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(isSaving ? 0.5 : 1)
                .accessibilityIdentifier("home_v2_log_sheet_save")
                if let onDelete {
                    Button(action: onDelete) {
                        Text(HomeV2ContextCopy.deleteEntry)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home_v2_log_sheet_delete")
                }
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .padding(.vertical, HomeV2Tokens.Space.tight)
        .background(HomeV2Tokens.Colors.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_v2_edit_actions")
    }

    private var supportingWeight: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                    supportingWeightLabel
                    weightControl
                }
            } else {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    supportingWeightLabel
                    weightControl
                }
            }
        }
        .padding(.vertical, HomeV2Tokens.Space.tight)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
    }

    private var weightControl: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: HomeV2Tokens.Space.tight) {
                    weightValue
                    HStack {
                        stepButton(direction: -1)
                        Spacer(minLength: HomeV2Tokens.Space.tight)
                        stepButton(direction: 1)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    stepButton(direction: -1)
                    weightValue
                    stepButton(direction: 1)
                }
            }
        }
    }

    private var weightValue: some View {
        HStack(spacing: 4) {
            TextField("", text: $valueText, prompt: Text("Add").foregroundColor(HomeV2Tokens.Colors.secondary))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .scaledSystemFont(size: 20, weight: .semibold, relativeTo: .title3)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .focused(focusedField, equals: .weight)
                .accessibilityLabel("Weight")
                .accessibilityIdentifier("home_v2_log_sheet_value")
            if !initialWeightIsMissing || !valueText.isEmpty {
                Text(unit)
                    .scaledSystemFont(size: 20, relativeTo: .title3)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(direction: Int) -> some View {
        Button { onStep(direction) } label: {
            Image(systemName: direction < 0 ? "minus" : "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? "Decrease weight" : "Increase weight")
        .accessibilityIdentifier(direction < 0 ? "home_v2_log_sheet_minus" : "home_v2_log_sheet_plus")
    }

    private var primaryDate: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                    Text("Date").foregroundStyle(HomeV2Tokens.Colors.secondary)
                    Text(dateText).accessibilityIdentifier("home_v2_edit_date_text")
                }
            } else {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    Text("Date").foregroundStyle(HomeV2Tokens.Colors.secondary)
                    Spacer(minLength: HomeV2Tokens.Space.tight)
                    Text(dateText).accessibilityIdentifier("home_v2_edit_date_text")
                }
            }
        }
        .scaledSystemFont(size: 16, relativeTo: .subheadline)
        .foregroundStyle(HomeV2Tokens.Colors.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.bottom, HomeV2Tokens.Space.tight)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_v2_log_sheet_date")
    }

    private var primaryBodyFat: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            Text(HomeV2Copy.bodyFat)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home_v2_edit_body_fat_label")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    primaryBodyFatField
                    primaryBodyFatUnit
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    primaryBodyFatField
                    primaryBodyFatUnit
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var primaryBodyFatField: some View {
        TextField("", text: $bodyFatText,
                  prompt: Text(HomeV2Copy.bodyFatPlaceholder).foregroundColor(HomeV2Tokens.Colors.secondary))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.leading)
            .font(HomeV2Tokens.Editor.display(size: 84, weight: .thin, relativeTo: .largeTitle))
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .focused(focusedField, equals: .bodyFat)
            .accessibilityLabel("Body fat percent")
            .accessibilityIdentifier("home_v2_log_sheet_body_fat")
    }

    private var primaryBodyFatUnit: some View {
        Text("%")
            .scaledSystemFont(size: 28, relativeTo: .title2)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .accessibilityIdentifier("home_v2_edit_body_fat_unit")
    }

    private var primaryValidationSlot: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorText {
                Text(errorText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home_v2_log_sheet_error")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
    }

    private var supportingWeightLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weight")
            if initialWeightIsMissing && valueText.isEmpty {
                Text("Not logged").accessibilityLabel("Weight not logged")
            }
        }
        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
        .foregroundStyle(HomeV2Tokens.Colors.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var progressPhotoAction: some View {
        let title = existingPhotoURL == nil ? "Add progress photo" : "Replace progress photo"
        let photoHeight: CGFloat = 68
        let previewHeight = photoHeight - 2 * HomeV2Tokens.Space.row
        return Button {
            // Preserve the existing callback contract; the generic owner ignores its legacy pose argument.
            onAddPhoto()
        } label: {
            HStack(spacing: HomeV2Tokens.Space.compact) {
                if let existingPhotoURL {
                    SubjectPlateView(
                        urlString: existingPhotoURL,
                        size: CGSize(width: previewHeight * 0.75, height: previewHeight)
                    )
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .padding(HomeV2Tokens.Space.row)
            .frame(maxWidth: .infinity, minHeight: photoHeight)
            .background(
                HomeV2Tokens.Colors.card,
                in: RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        // Keep the existing protected photo-control identifier used by the native interaction scanner.
        .accessibilityIdentifier("home_v2_log_sheet_photo_front")
    }
}
