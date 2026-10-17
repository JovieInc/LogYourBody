//
// HomeV2LogWeightSheet.swift
// LogYourBody
//
import SwiftUI

/// Log weight (Pencil L1/L1a): the number with −/+ steps or typing, optional
/// details behind one disclosure, one Save action. Persistence stays with the
/// caller; the sheet reports success or shows why it could not save.
struct HomeV2LogWeightSheet: View {
    enum Mode {
        case log
        case edit
    }

    let mode: Mode
    let unit: String
    let initialValue: Double
    let initialBodyFat: Double?
    let initialWeightIsMissing: Bool
    let dateText: String
    let deleteScope: String?
    /// The day's existing photo, shown in the Front slot instead of a camera.
    let existingPhotoURL: String?
    let onSave: (_ value: Double?, _ bodyFat: Double?) async -> Bool
    let onCorrectionSave: ((
        HomeV2CorrectionPolicy.Changes, AuthManager.ProfileSessionOwnership?,
        HomeV2CorrectionReturnReceipt?, @escaping @MainActor () -> Bool
    ) async -> Bool)?
    let ownsCorrectionSession: (AuthManager.ProfileSessionOwnership) -> Bool
    let initialBodyFatMethod: String?
    let currentCorrectionOwnership: AuthManager.ProfileSessionOwnership?
    let currentCorrectionReturnDestination: HomeV2ContextRoute?
    let onCorrectionReturnEnded: (HomeV2CorrectionReturnReceipt) -> Void
    let onDelete: (() async -> Bool)?
    let onAddPhoto: (_ pose: String) -> Void

    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    @Environment(\.homeV2CorrectionFixtureHold) private var correctionFixtureHold
    @Environment(\.homeV2CorrectionFixtureGraph) private var correctionFixtureGraph
    @State private var fixtureMountedReceipt: HomeV2CorrectionReturnReceipt?
    #endif
    @State private var bodyFatMethod: String?
    @State private var correctionOwnership: AuthManager.ProfileSessionOwnership?
    @State private var correctionReturnDestination: HomeV2ContextRoute?
    @State private var correctionTask: Task<Void, Never>?
    @State private var correctionLifetime = UUID()
    @State private var correctionInvalidated = false
    @State private var valueText: String
    @State private var preservesRecordedValues: Bool
    @State private var bodyFatPrimary: Bool
    @State private var bodyFatText: String
    @State private var showsDetails: Bool
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var errorText: String?
    @State private var validationErrorField: Field?
    @State private var detent: PresentationDetent
    @FocusState private var focusedField: Field?

    private typealias Field = HomeV2EntryEditorField

    init(
        mode: Mode = .log,
        unit: String,
        initialValue: Double,
        initialBodyFat: Double?,
        initialWeightIsMissing: Bool = false,
        initialBodyFatMethod: String? = nil,
        correctionOwnership: AuthManager.ProfileSessionOwnership? = nil,
        correctionReturnDestination: HomeV2ContextRoute? = nil,
        onCorrectionReturnEnded: @escaping (HomeV2CorrectionReturnReceipt) -> Void = { _ in },
        ownsCorrectionSession: @escaping (AuthManager.ProfileSessionOwnership) -> Bool = { _ in false },
        dateText: String,
        deleteScope: String? = nil,
        existingPhotoURL: String? = nil,
        onSave: @escaping (_ value: Double?, _ bodyFat: Double?) async -> Bool,
        onCorrectionSave: ((
            HomeV2CorrectionPolicy.Changes, AuthManager.ProfileSessionOwnership?,
            HomeV2CorrectionReturnReceipt?, @escaping @MainActor () -> Bool
        ) async -> Bool)? = nil,
        onDelete: (() async -> Bool)? = nil,
        onAddPhoto: @escaping (_ pose: String) -> Void
    ) {
        self.mode = mode
        self.unit = unit
        self.initialValue = initialValue
        self.initialBodyFat = initialBodyFat
        self.initialWeightIsMissing = initialWeightIsMissing
        self.dateText = dateText
        self.deleteScope = deleteScope
        self.existingPhotoURL = existingPhotoURL
        self.onSave = onSave
        self.onCorrectionSave = onCorrectionSave
        self.ownsCorrectionSession = ownsCorrectionSession
        self.initialBodyFatMethod = initialBodyFatMethod
        self.currentCorrectionOwnership = correctionOwnership
        self.currentCorrectionReturnDestination = correctionReturnDestination
        self.onCorrectionReturnEnded = onCorrectionReturnEnded
        _correctionReturnDestination = State(initialValue: correctionReturnDestination)
        _bodyFatMethod = State(initialValue: BodyFatEntryMethod.initialSelection(
            bodyFat: initialBodyFat, recordedMethod: initialBodyFatMethod
        ))
        _correctionOwnership = State(initialValue: correctionOwnership)
        self.onDelete = onDelete
        self.onAddPhoto = onAddPhoto
        // Hold the policy for this presentation; a flag refresh must not replace a focused draft.
        let primary = mode == .edit && HomeV2EntryBodyFatPrimaryPolicy.isEnabled()
        _bodyFatPrimary = State(initialValue: primary)
        let preservesRecordedValues = onCorrectionSave != nil || primary
            || (mode == .edit && HomeV2EntryEditPolicy.isEnabled())
        _preservesRecordedValues = State(initialValue: preservesRecordedValues)
        _valueText = State(initialValue: preservesRecordedValues && initialWeightIsMissing
            ? "" : HomeV2WeightStepPolicy.text(initialValue))
        _bodyFatText = State(initialValue: initialBodyFat.map { String(format: "%.1f", $0) } ?? "")
        _showsDetails = State(initialValue: mode == .edit)
        _detent = State(initialValue: mode == .edit ? .large : .medium)
    }

    private var title: String {
        mode == .edit ? HomeV2ContextCopy.editEntry : HomeV2Copy.logSheetTitle
    }

    private var saveTitle: String {
        mode == .edit ? HomeV2ContextCopy.saveChanges : HomeV2Copy.saveWeight
    }

    private var isCorrectionCurrent: Bool {
        guard !correctionInvalidated,
              HomeV2CorrectionPolicy.isEditorCurrent(
                original: correctionOwnership, current: currentCorrectionOwnership
              ), let ownership = correctionOwnership else { return false }
        guard ownsCorrectionSession(ownership) else { return false }
        if let destination = correctionReturnDestination {
            return destination.id == currentCorrectionReturnDestination?.id
                && destination.ownership == currentCorrectionReturnDestination?.ownership
        }
        return currentCorrectionReturnDestination == nil
    }

    var body: some View {
        Group {
            if onCorrectionSave == nil || isCorrectionCurrent {
                editorContent
            } else {
                Color.clear
            }
        }
        .onChange(of: currentCorrectionOwnership) { _, _ in
            if onCorrectionSave != nil, !isCorrectionCurrent { invalidateCorrection() }
        }
        .onAppear {
            #if DEBUG
            if correctionFixtureGraph != nil, onCorrectionSave != nil, fixtureMountedReceipt == nil,
               let destination = correctionReturnDestination {
                fixtureMountedReceipt = .init(destination: destination, editorLifetime: correctionLifetime)
            }
            observeFixtureEditor(visible: true)
            #endif
            if onCorrectionSave != nil, !isCorrectionCurrent { invalidateCorrection() }
        }
        #if DEBUG
        .onChange(of: isSaving) { _, _ in observeFixtureEditor(visible: true) }
        .onChange(of: errorText) { _, _ in observeFixtureEditor(visible: true) }
        #endif
        .onChange(of: currentCorrectionReturnDestination?.id) { _, _ in
            if onCorrectionSave != nil, !isCorrectionCurrent { invalidateCorrection() }
        }
        #if DEBUG
        .safeAreaInset(edge: .top) {
            if let graph = correctionFixtureGraph, let receipt = fixtureMountedReceipt {
                HomeV2CorrectionFixturePanel(
                    graph: graph, editor: receipt, liveRoute: currentCorrectionReturnDestination, scope: "editor"
                )
            }
        }
        #endif
        .onDisappear {
            #if DEBUG
            observeFixtureEditor(visible: false)
            #endif
            if onCorrectionSave != nil {
                finishCorrectionReturn()
                correctionInvalidated = true
                correctionLifetime = UUID()
                correctionTask?.cancel()
                correctionTask = nil
                isSaving = false
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if bodyFatPrimary {
            HomeV2EntryEditorLayout(
                unit: unit, dateText: dateText, initialWeightIsMissing: initialWeightIsMissing,
                existingPhotoURL: existingPhotoURL, isSaving: isSaving, errorText: errorText,
                valueText: $valueText, bodyFatText: $bodyFatText, focusedField: $focusedField,
                onSave: save, onDelete: onDelete == nil ? nil : { isConfirmingDelete = true },
                onAddPhoto: { onAddPhoto("Front") }, onClose: { dismiss() }, onStep: step
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mode == .edit, onCorrectionSave != nil {
                    correctionMethodPicker
                        .padding(.horizontal, HomeV2Tokens.Space.margin)
                        .padding(.vertical, HomeV2Tokens.Space.tight)
                        .background(HomeV2Tokens.Colors.canvas)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(HomeV2Tokens.Colors.canvas)
            .onChange(of: focusedField) { previous, current in
                if previous == .weight, current != .weight { commitTypedWeight() }
            }
            .onChange(of: bodyFatText) { _, _ in clearSubmittedValidation(for: .bodyFat) }
            .onChange(of: valueText) { _, _ in clearSubmittedValidation(for: .weight) }
            .alert(HomeV2ContextCopy.deleteTitle, isPresented: $isConfirmingDelete) {
                Button(HomeV2ContextCopy.deleteEntry, role: .destructive, action: performDelete)
                    .accessibilityIdentifier("home_v2_log_sheet_delete_confirm")
                Button(HomeV2ContextCopy.cancel, role: .cancel) {}
                    .accessibilityIdentifier("home_v2_log_sheet_delete_cancel")
            } message: {
                Text(deleteScope ?? "")
            }
        } else {
            legacyContent
        }
    }

    private var legacyContent: some View {
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
                title: saveTitle,
                isEnabled: !isSaving,
                identifier: "home_v2_log_sheet_save",
                action: save
            )

            if onDelete != nil {
                Button {
                    isConfirmingDelete = true
                } label: {
                    Text(HomeV2ContextCopy.deleteEntry)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityIdentifier("home_v2_log_sheet_delete")
                // confirmationDialog presents without Cancel, so deleting an
                // entry has no reachable escape hatch.
                .alert(
                    HomeV2ContextCopy.deleteTitle,
                    isPresented: $isConfirmingDelete
                ) {
                    Button(HomeV2ContextCopy.deleteEntry, role: .destructive, action: performDelete)
                        .accessibilityIdentifier("home_v2_log_sheet_delete_confirm")
                    Button(HomeV2ContextCopy.cancel, role: .cancel) {}
                        .accessibilityIdentifier("home_v2_log_sheet_delete_cancel")
                } message: {
                    Text(deleteScope ?? "")
                }
            }
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
            Text(title)
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
                TextField("", text: $valueText, prompt: preservesRecordedValues && initialWeightIsMissing
                    ? Text("Add").foregroundColor(HomeV2Tokens.Colors.secondary) : nil)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetValue, weight: .semibold, relativeTo: .largeTitle)
                    .kerning(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
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

            if mode == .edit, onCorrectionSave != nil {
                correctionMethodPicker
            }

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

    private var correctionMethodPicker: some View {
        Picker("Method", selection: $bodyFatMethod) {
            if BodyFatEntryMethod.needsPreservedOption(bodyFatMethod) {
                Text(BodyFatEntryMethod.selectionTitle(bodyFatMethod)).tag(bodyFatMethod)
            }
            ForEach(BodyFatEntryMethod.allCases, id: \.rawValue) { method in
                Text(method.title).tag(Optional(method.rawValue))
            }
        }
        .pickerStyle(.menu)
        .disabled(isSaving)
        .accessibilityLabel("Body fat measurement method")
        .accessibilityValue(BodyFatEntryMethod.selectionTitle(bodyFatMethod))
        .accessibilityIdentifier("home_v2_edit_body_fat_method")
    }

    private func photoSlot(_ pose: String) -> some View {
        let showsExisting = pose == HomeV2Copy.poses.first && existingPhotoURL != nil
        return Button {
            onAddPhoto(pose)
        } label: {
            ZStack(alignment: .bottom) {
                if showsExisting, let existingPhotoURL {
                    GeometryReader { geometry in
                        SubjectPlateView(
                            urlString: existingPhotoURL,
                            size: CGSize(width: geometry.size.width, height: HomeV2Tokens.photoSlotHeight)
                        )
                    }
                    Text(pose)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, weight: .medium, relativeTo: .caption)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .padding(.horizontal, HomeV2Tokens.Space.tight)
                        .padding(.vertical, HomeV2Tokens.Space.tight / 2)
                        .background(HomeV2Tokens.Colors.canvas.opacity(0.65), in: Capsule())
                        .padding(.bottom, HomeV2Tokens.Space.tight)
                } else {
                    VStack(spacing: HomeV2Tokens.Space.tight) {
                        Image(systemName: "camera")
                            .font(.system(size: 20, weight: .medium))
                        Text(pose)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    }
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .frame(maxWidth: .infinity, minHeight: HomeV2Tokens.photoSlotHeight)
                }
            }
            .frame(maxWidth: .infinity, minHeight: HomeV2Tokens.photoSlotHeight)
            .background(
                HomeV2Tokens.Colors.card,
                in: RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsExisting ? "Retake \(pose) photo" : "Add \(pose) photo")
        .accessibilityIdentifier("home_v2_log_sheet_photo_\(pose.lowercased())")
    }

    private func clearSubmittedValidation(for field: Field) {
        guard validationErrorField == field else { return }
        validationErrorField = nil
        errorText = nil
    }

    private func step(_ direction: Int) {
        validationErrorField = nil
        let current = HomeV2WeightStepPolicy.parse(valueText) ?? initialValue
        valueText = HomeV2WeightStepPolicy.text(HomeV2WeightStepPolicy.stepped(current, by: direction, unit: unit))
        errorText = nil
        HapticManager.shared.selection()
    }

    private func commitTypedWeight() {
        if preservesRecordedValues {
            do {
                _ = try HomeV2EntryEditPolicy.weight(
                    text: valueText, initialValue: initialWeightIsMissing ? nil : initialValue,
                    unit: unit, preserving: true
                )
                if !bodyFatPrimary || validationErrorField != .bodyFat {
                    validationErrorField = nil
                    errorText = nil
                }
            } catch {
                validationErrorField = .weight
                errorText = error.localizedDescription
            }
            return
        }
        guard let typed = HomeV2WeightStepPolicy.parse(valueText) else { return }
        valueText = HomeV2WeightStepPolicy.text(typed)
        errorText = HomeV2WeightStepPolicy.range(unit: unit).contains(typed)
            ? nil
            : HomeV2Copy.weightRangeError(unit: unit)
    }

    private func performDelete() {
        guard !isSaving, onCorrectionSave == nil || isCorrectionCurrent, let onDelete else { return }
        focusedField = nil
        isSaving = true
        let lifetime = correctionLifetime
        Task { @MainActor in
            let deleted = await onDelete()
            if onCorrectionSave != nil {
                guard !Task.isCancelled, correctionLifetime == lifetime, isCorrectionCurrent else { return }
            }
            isSaving = false
            if deleted {
                dismiss()
            } else {
                errorText = HomeV2ContextCopy.deleteFailed
            }
        }
    }

    #if DEBUG
    private func observeFixtureEditor(visible: Bool) {
        guard let graph = correctionFixtureGraph, let receipt = fixtureMountedReceipt else { return }
        graph.observeEditor(.init(
            receipt: receipt, visible: visible, isSaving: isSaving, error: errorText,
            invalidated: correctionInvalidated, currentLifetime: correctionLifetime
        ))
    }
    #endif

    private func finishCorrectionReturn() {
        guard let destination = correctionReturnDestination else { return }
        onCorrectionReturnEnded(.init(destination: destination, editorLifetime: correctionLifetime))
    }

    private func invalidateCorrection() {
        guard onCorrectionSave != nil else { return }
        finishCorrectionReturn()
        #if DEBUG
        if let destination = correctionReturnDestination {
            correctionFixtureHold?.recordCancellation(.init(
                destination: destination, editorLifetime: correctionLifetime
            ))
        }
        #endif
        correctionInvalidated = true
        correctionLifetime = UUID()
        correctionTask?.cancel()
        correctionTask = nil
        isSaving = false
        dismiss()
    }

    private func saveCorrection(
        using save: @escaping (
            HomeV2CorrectionPolicy.Changes, AuthManager.ProfileSessionOwnership?,
            HomeV2CorrectionReturnReceipt?, @escaping @MainActor () -> Bool
        ) async -> Bool
    ) {
        guard !isSaving, isCorrectionCurrent, let ownership = correctionOwnership else { return }
        focusedField = nil
        let weight: Double?
        let bodyFat: Double?
        do {
            validationErrorField = .weight
            weight = try HomeV2EntryEditPolicy.weight(
                text: valueText, initialValue: initialWeightIsMissing ? nil : initialValue,
                unit: unit, preserving: true
            )
            validationErrorField = .bodyFat
            bodyFat = try HomeV2EntryEditPolicy.bodyFat(
                text: bodyFatText, initialValue: initialBodyFat, preserving: true
            )
        } catch {
            errorText = error.localizedDescription
            return
        }
        validationErrorField = nil

        // The editor shows rounded values. Returning to that display is a no-op,
        // including for imported values whose stored precision or range differs.
        let displayedWeight = initialWeightIsMissing ? nil
            : HomeV2WeightStepPolicy.parse(HomeV2WeightStepPolicy.text(initialValue))
        let displayedBodyFat = initialBodyFat.flatMap {
            HomeV2WeightStepPolicy.parse(String(format: "%.1f", $0))
        }
        var changes = HomeV2CorrectionPolicy.Changes()
        if weight != displayedWeight, let weight {
            changes.weight = .kilograms(unit == "lb" ? weight.lbsToKg : weight)
        }
        if bodyFat != displayedBodyFat {
            if let bodyFat {
                changes.bodyFat = .reading(bodyFat, method: bodyFatMethod)
            } else if initialBodyFat != nil {
                changes.bodyFat = .clear
            }
        } else if bodyFatMethod != BodyFatEntryMethod.initialSelection(
            bodyFat: initialBodyFat, recordedMethod: initialBodyFatMethod
        ), let initialBodyFat {
            // A method-only correction must retain the original raw reading.
            changes.bodyFat = .reading(initialBodyFat, method: bodyFatMethod)
        }
        errorText = nil
        isSaving = true
        let lifetime = correctionLifetime
        correctionTask = Task { @MainActor in
            let receipt = correctionReturnDestination.map {
                HomeV2CorrectionReturnReceipt(destination: $0, editorLifetime: lifetime)
            }
            let saved = await save(changes, ownership, receipt, {
                !Task.isCancelled && correctionLifetime == lifetime && isCorrectionCurrent
            })
            guard !Task.isCancelled, correctionLifetime == lifetime else { return }
            guard isCorrectionCurrent else {
                invalidateCorrection()
                return
            }
            isSaving = false
            correctionTask = nil
            if saved { dismiss() } else { errorText = HomeV2Copy.saveFailed }
        }
        #if DEBUG
        if let correctionTask, let destination = correctionReturnDestination {
            correctionFixtureHold?.observeTask(correctionTask, receipt: .init(
                destination: destination, editorLifetime: lifetime
            ))
        }
        #endif
    }

    private func save() {
        if mode == .edit, let onCorrectionSave {
            saveCorrection(using: onCorrectionSave)
            return
        }
        guard !isSaving else { return }
        focusedField = nil
        let value: Double?
        let bodyFat: Double?
        do {
            validationErrorField = .weight
            value = try HomeV2EntryEditPolicy.weight(
                text: valueText, initialValue: initialWeightIsMissing ? nil : initialValue,
                unit: unit, preserving: preservesRecordedValues
            )
            validationErrorField = .bodyFat
            bodyFat = try HomeV2EntryEditPolicy.bodyFat(
                text: bodyFatText, initialValue: initialBodyFat, preserving: preservesRecordedValues
            )
        } catch {
            errorText = error.localizedDescription
            return
        }

        validationErrorField = nil
        errorText = nil
        isSaving = true
        Task { @MainActor in
            let saved = await onSave(value, bodyFat)
            isSaving = false
            if saved {
                if value != nil { NotificationManager.shared.recordWeighInLogged() }
                dismiss()
            } else {
                errorText = HomeV2Copy.saveFailed
            }
        }
    }
}
