//
// HomeV2OnboardingViews.swift
// LogYourBody
//
import SwiftUI

extension LegalDocumentView.LegalDocumentType: Identifiable {
    public var id: String { String(describing: self) }
}

enum HomeV2OnboardingCopy {
    static let brand = "LogYourBody"
    static let signInTitle = "See how you’re really doing."
    static let signInBody = "Weight, body fat and progress photos from Apple Health, on one timeline."
    static let continueWithApple = "Continue with Apple"
    static let openingApple = "Opening Apple…"
    static let legalPrefix = "By continuing you agree to the"
    static let terms = "Terms"
    static let privacy = "Privacy Policy"
    static let connectHealthTitle = "Connect Apple Health"
    static let connectHealthBody = "We read your data so you don’t have to log it. Nothing is written back."
    static let readWeight = "Weight"
    static let readWeightDetail = "Measured, from your scale or app"
    static let readBodyFat = "Body fat"
    static let readBodyFatDetail = "Estimated, when a source provides it"
    static let readSteps = "Steps"
    static let readStepsDetail = "Daily totals from your iPhone or watch"
    static let notNow = "Not now"
    static let targetTitle = "Set a target"
    static let targetBody =
        "Your target is yours to choose. It’s used to show pace and to flag when a phase has likely gone on too long."
    static let targetWeight = "Target weight"
    static let moreTargetOptions = "More target options"
    static let bodyFatTarget = "Body fat target"
    static let targetNote = "Weight from Apple Health is measured. Body fat is estimated."
    static let saveTarget = "Save target"
    static let skipForNow = "Skip for now"
    static let saveFailed = "Could not save. Check your connection and try again."
    static let included = [
        "Unlimited progress photos and compare",
        "Body-fat, lean mass and FFMI trends",
        "Phase insights that tell you when to stop cutting"
    ]
    static let stepsCount = 3

    static func targetRangeError(unit: String) -> String {
        HomeV2Copy.weightRangeError(unit: unit)
    }
}

/// Three quiet bars: where you are in the first run (Pencil "Steps").
struct HomeV2StepMarkers: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: HomeV2Tokens.Space.tight) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.borderStrong)
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

/// A quiet full-width text action (Not now, Skip for now, Restore purchases).
struct HomeV2QuietAction: View {
    let title: String
    let identifier: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
    }
}

/// Sign in (Pencil O1): the promise, one Apple action, the legal line.
struct HomeV2SignInView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var legalDocument: LegalDocumentView.LegalDocumentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
                Text(HomeV2OnboardingCopy.brand)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Text(HomeV2OnboardingCopy.signInTitle)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.heroPhoto, weight: .bold, relativeTo: .largeTitle)
                    .kerning(-1)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home_v2_sign_in")
                Text(HomeV2OnboardingCopy.signInBody)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText {
                Text(errorText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.red)
                    .padding(.top, HomeV2Tokens.Space.compact)
                    .accessibilityIdentifier("home_v2_sign_in_error")
            }

            HomeV2PrimaryButton(
                title: isLoading ? HomeV2OnboardingCopy.openingApple : HomeV2OnboardingCopy.continueWithApple,
                systemImage: "apple.logo",
                isEnabled: !isLoading,
                identifier: "home_v2_sign_in_apple",
                action: authenticate
            )
            .padding(.top, HomeV2Tokens.Space.margin)

            legalLine
                .padding(.top, HomeV2Tokens.Space.compact)
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .padding(.bottom, HomeV2Tokens.Space.margin)
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(documentType: document) }
        }
        .onAppear { AppServicePorts.analyticsTracker.track(event: "login_view") }
    }

    private var legalLine: some View {
        HStack(spacing: 4) {
            Text(HomeV2OnboardingCopy.legalPrefix)
            Button(HomeV2OnboardingCopy.terms) { legalDocument = .terms }
                .buttonStyle(.plain)
                .underline()
            Text("and")
            Button(HomeV2OnboardingCopy.privacy) { legalDocument = .privacy }
                .buttonStyle(.plain)
                .underline()
        }
        .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
        .foregroundStyle(HomeV2Tokens.Colors.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func authenticate() {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        AppServicePorts.analyticsTracker.track(event: "login_attempt", properties: ["method": "apple"])
        Task { @MainActor in
            defer { isLoading = false }
            do {
                try await authManager.signInWithApple()
            } catch AuthError.cancelled {
                return
            } catch {
                errorText = authManager.loginErrorMessage(for: error)
                AppServicePorts.analyticsTracker.track(event: "login_failed", properties: ["method": "apple"])
            }
        }
    }
}

/// First run after sign-in (Pencil O2 → O3): connect Apple Health, set a
/// target, both optional, then Home. Completion is durable before it counts.
struct HomeV2FirstRunView: View {
    private enum Step {
        case health
        case target
    }

    @EnvironmentObject private var authManager: AuthManager
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @State private var step: Step = .health
    @State private var isBusy = false
    @State private var targetText = ""
    @State private var bodyFatText = ""
    @State private var showsMoreTargets = false
    @State private var errorText: String?

    private var system: MeasurementSystem { MeasurementSystem.fromStored(rawValue: measurementSystem) }
    private var unit: String { HomeV2Copy.displayUnit(system) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
                HomeV2StepMarkers(current: step == .health ? 1 : 2, total: HomeV2OnboardingCopy.stepsCount)
                Text(step == .health ? HomeV2OnboardingCopy.connectHealthTitle : HomeV2OnboardingCopy.targetTitle)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.lead + 4, weight: .bold, relativeTo: .title)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(step == .health ? "home_v2_first_run_health" : "home_v2_first_run_target")
                Text(step == .health ? HomeV2OnboardingCopy.connectHealthBody : HomeV2OnboardingCopy.targetBody)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.top, HomeV2Tokens.Space.heroTop)

            Group {
                if step == .health {
                    reads
                } else {
                    targetTable
                }
            }
            .padding(.top, HomeV2Tokens.Space.compact)

            if let errorText {
                Text(errorText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.red)
                    .padding(.horizontal, HomeV2Tokens.Space.margin)
                    .padding(.top, HomeV2Tokens.Space.row)
                    .accessibilityIdentifier("home_v2_first_run_error")
            }

            Spacer(minLength: 0)

            VStack(spacing: HomeV2Tokens.Space.row) {
                if step == .health {
                    HomeV2PrimaryButton(
                        title: HomeV2OnboardingCopy.connectHealthTitle,
                        isEnabled: !isBusy,
                        identifier: "home_v2_first_run_connect",
                        action: connectHealth
                    )
                    HomeV2QuietAction(
                        title: HomeV2OnboardingCopy.notNow,
                        identifier: "home_v2_first_run_not_now",
                        isEnabled: !isBusy
                    ) { step = .target }
                } else {
                    HomeV2PrimaryButton(
                        title: HomeV2OnboardingCopy.saveTarget,
                        isEnabled: !isBusy,
                        identifier: "home_v2_first_run_save_target",
                        action: { Task { await complete(savingTarget: true) } }
                    )
                    HomeV2QuietAction(
                        title: HomeV2OnboardingCopy.skipForNow,
                        identifier: "home_v2_first_run_skip",
                        isEnabled: !isBusy
                    ) { Task { await complete(savingTarget: false) } }
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.bottom, HomeV2Tokens.Space.compact)
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var reads: some View {
        VStack(spacing: 0) {
            readRow(HomeV2OnboardingCopy.readWeight, detail: HomeV2OnboardingCopy.readWeightDetail, systemImage: "scalemass")
            readRow(HomeV2OnboardingCopy.readBodyFat, detail: HomeV2OnboardingCopy.readBodyFatDetail, systemImage: "percent")
            readRow(HomeV2OnboardingCopy.readSteps, detail: HomeV2OnboardingCopy.readStepsDetail, systemImage: "figure.walk")
        }
        .overlay(alignment: .top) { HomeV2Hairline() }
    }

    private func readRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: HomeV2Tokens.Space.compact) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                Text(detail)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .frame(minHeight: 75)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityElement(children: .combine)
    }

    private var targetTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2OnboardingCopy.targetWeight)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                Spacer(minLength: HomeV2Tokens.Space.tight)
                TextField(HomeV2SettingsCopy.notSet, text: $targetText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: 88)
                    .accessibilityLabel(HomeV2OnboardingCopy.targetWeight)
                    .accessibilityIdentifier("home_v2_first_run_target_weight")
                Text(unit)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .frame(minHeight: 56)
            .overlay(alignment: .top) { HomeV2Hairline() }
            .overlay(alignment: .bottom) { HomeV2Hairline() }

            if showsMoreTargets {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    Text(HomeV2OnboardingCopy.bodyFatTarget)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                    Spacer(minLength: HomeV2Tokens.Space.tight)
                    TextField(HomeV2SettingsCopy.notSet, text: $bodyFatText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .semibold, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .frame(width: 88)
                        .accessibilityLabel(HomeV2OnboardingCopy.bodyFatTarget)
                    Text("%")
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                }
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .frame(minHeight: 56)
                .overlay(alignment: .bottom) { HomeV2Hairline() }
            } else {
                HomeV2DisclosureLink(
                    title: HomeV2OnboardingCopy.moreTargetOptions,
                    identifier: "home_v2_first_run_more_targets"
                ) { showsMoreTargets = true }
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .frame(minHeight: HomeV2Tokens.rowHeight)
            }

            Text(HomeV2OnboardingCopy.targetNote)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .padding(.top, HomeV2Tokens.Space.compact)
        }
    }

    private func connectHealth() {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            _ = await HealthKitManager.shared.requestAuthorization()
            isBusy = false
            step = .target
        }
    }

    /// Saves any target locally, then marks onboarding complete on the
    /// server before the local flag flips, so a failed save never strands
    /// the person in an app that thinks it finished.
    @MainActor
    private func complete(savingTarget: Bool) async {
        guard !isBusy else { return }
        errorText = nil
        if savingTarget {
            let trimmed = targetText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                guard let value = HomeV2WeightStepPolicy.parse(trimmed),
                      HomeV2WeightStepPolicy.range(unit: unit).contains(value),
                      let kilograms = WeightGoal(displayValue: value, measurementSystem: system)?.kilograms else {
                    errorText = HomeV2OnboardingCopy.targetRangeError(unit: unit)
                    return
                }
                UserDefaults.standard.set(kilograms, forKey: Constants.goalWeightKilogramsKey)
            }
            let bodyFatTrimmed = bodyFatText.trimmingCharacters(in: .whitespaces)
            if !bodyFatTrimmed.isEmpty {
                guard let bodyFat = HomeV2WeightStepPolicy.parse(bodyFatTrimmed),
                      HomeV2WeightStepPolicy.bodyFatRange.contains(bodyFat) else {
                    errorText = HomeV2Copy.bodyFatRangeError
                    return
                }
                UserDefaults.standard.set(bodyFat, forKey: Constants.goalBodyFatPercentageKey)
            }
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await authManager.updateProfileDurably(["onboardingCompleted": true])
        } catch {
            errorText = HomeV2OnboardingCopy.saveFailed
            return
        }
        OnboardingStateManager.shared.markCompleted(userId: authManager.currentUser?.id)
        HapticManager.shared.successAction()
    }
}
