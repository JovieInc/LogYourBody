import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @StateObject private var viewModel = OnboardingFlowViewModel()
    @State private var showLoginSheet = false
    private let onboardingStateManager = OnboardingStateManager.shared
    @State private var hasPresentedPaywall = false

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            HookScreen(viewModel: viewModel) {
                showLoginSheet = true
            }
            .navigationDestination(for: OnboardingFlowViewModel.Step.self) { step in
                switch step {
                case .basics:
                    BasicsScreen(viewModel: viewModel)
                case .height:
                    HeightScreen(viewModel: viewModel)
                case .healthConnect:
                    HealthConnectScreen(viewModel: viewModel)
                case .manualWeight:
                    WeightScreen(viewModel: viewModel)
                case .bodyFatKnowledge:
                    BodyFatKnowledgeScreen(viewModel: viewModel)
                case .bodyFatNumeric:
                    BodyFatNumericScreen(viewModel: viewModel)
                case .bodyFatVisual:
                    BodyFatVisualScreen(viewModel: viewModel)
                case .loading:
                    LoadingScreen()
                case .score:
                    BodyScoreRevealScreen(viewModel: viewModel)
                case .account:
                    AccountCreationScreen(viewModel: viewModel)
                        .environmentObject(authManager)
                case .paywall:
                    PaywallView()
                        .environmentObject(authManager)
                        .environmentObject(revenueCatManager)
                case .hook:
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            NavigationStack {
                LoginView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showLoginSheet = false }
                        }
                    }
            }
            .environmentObject(authManager)
        }
        .sheet(isPresented: $viewModel.showEmailSheet) {
            EmailCaptureSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: Binding(
            get: { authManager.needsEmailVerification },
            set: { _ in }
        )) {
            NavigationStack {
                EmailVerificationView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                authManager.needsEmailVerification = false
                            }
                        }
                    }
            }
            .environmentObject(authManager)
        }
        .onChange(of: revenueCatManager.isSubscribed) { _, isSubscribed in
            if isSubscribed {
                onboardingStateManager.markCompleted()
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && viewModel.bodyScoreResult != nil && !hasPresentedPaywall {
                hasPresentedPaywall = true
                viewModel.proceedToPaywall()
            }
        }
        .onAppear {
            hasPresentedPaywall = false
        }
    }
}

// MARK: - Pages

private struct HookScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    let onLogin: () -> Void

    var body: some View {
        OnboardingScreenContainer {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingTitleText(text: "Get your Body Score")
                OnboardingSubtitleText(text: "See how good you look on paper – based on muscle, leanness, and aesthetics.")
                VStack(spacing: 16) {
                    BulletRow(symbol: "bolt.fill", text: "Estimate your Body Score in 60 seconds")
                    BulletRow(symbol: "chart.bar.xaxis", text: "See how you compare to people like you")
                    BulletRow(symbol: "gauge.medium", text: "Get a live HUD for your physique")
                }
                Button("Get my Body Score") {
                    viewModel.start()
                }
                .buttonStyle(PrimaryCTAButtonStyle())

                Button("Already have an account? Log in") {
                    onLogin()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BasicsScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        Form {
            Section(header: Text("Let’s start with the basics")) {
                Picker("Sex at birth", selection: $viewModel.sex) {
                    ForEach(BodyScoreCalculator.Input.Sex.allCases) { sex in
                        Text(sex.rawValue)
                    }
                }
                Picker("Birth year", selection: $viewModel.birthYear) {
                    ForEach(viewModel.yearOptions, id: \.self) { year in
                        Text("\(year)").tag(year)
                    }
                }
            }

            Section(footer: Text("We use this to interpret your body metrics correctly.")) {
                Button("Continue") {
                    viewModel.goToHeight()
                }
            }
        }
        .navigationTitle("Basics")
    }
}

private struct HeightScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    private let centimeterFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        formatter.minimum = 120
        formatter.maximum = 240
        return formatter
    }()

    var body: some View {
        Form {
            Section(header: Text("How tall are you?")) {
                Picker("Units", selection: $viewModel.heightUnit) {
                    Text("ft + in").tag(UnitToggleRow.Unit.imperial)
                    Text("cm").tag(UnitToggleRow.Unit.metric)
                }
                .pickerStyle(.segmented)

                if viewModel.heightUnit == .imperial {
                    Stepper(value: $viewModel.heightFeet, in: 4...7) {
                        Text("Feet: \(viewModel.heightFeet)")
                    }
                    Stepper(value: $viewModel.heightInches, in: 0...11) {
                        Text("Inches: \(viewModel.heightInches)")
                    }
                } else {
                    TextField("Centimeters", value: $viewModel.heightCentimeters, formatter: centimeterFormatter)
                        .keyboardType(.numberPad)
                }
            }
            Section(footer: Text("We use this to calculate your muscle index (FFMI).")) {
                Button("Continue") {
                    viewModel.goToHealthConnect()
                }
            }
        }
        .navigationTitle("Height")
        .onChange(of: viewModel.heightUnit) { newValue in
            switch newValue {
            case .imperial:
                let totalInches = Int(viewModel.heightCentimeters / 2.54)
                viewModel.heightFeet = max(4, totalInches / 12)
                viewModel.heightInches = max(0, totalInches % 12)
            case .metric:
                let inches = Double((viewModel.heightFeet * 12) + viewModel.heightInches)
                viewModel.heightCentimeters = inches * 2.54
            }
        }
    }
}

private struct HealthConnectScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        OnboardingScreenContainer {
            OnboardingTitleText(text: "Connect to Apple Health?")
            OnboardingSubtitleText(text: "We’ll auto-fill your weight, body fat %, and more. You stay in control of what we see.")

            if let summary = viewModel.healthSummary, viewModel.didConnectHealthKit {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Here’s what we found")
                        .font(.headline)
                    ForEach(summary.displayRows, id: \.self) { row in
                        Text(row)
                            .font(.body)
                    }
                    Button("Looks right") {
                        viewModel.confirmHealthImport()
                    }
                    .buttonStyle(PrimaryCTAButtonStyle())
                    Button("Edit") {
                        viewModel.editImportedMetrics()
                    }
                    .buttonStyle(SecondaryCTAButtonStyle())
                }
            } else {
                Button(action: {
                    Task { await viewModel.connectHealthKit() }
                }) {
                    HStack {
                        if viewModel.isRequestingHealthKit {
                            ProgressView()
                        }
                        Text(viewModel.isRequestingHealthKit ? "Connecting…" : "Connect Apple Health")
                    }
                }
                .buttonStyle(PrimaryCTAButtonStyle())
                Button("Not now") {
                    viewModel.goToManualWeightIfNeeded()
                }
                .buttonStyle(SecondaryCTAButtonStyle())
            }
        }
    }
}

private struct WeightScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var weightText: String = ""

    var body: some View {
        OnboardingScreenContainer {
            OnboardingTitleText(text: "What do you weigh right now?")
            TextField("Weight", text: $weightText)
                .keyboardType(.decimalPad)
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Picker("Units", selection: $viewModel.weightUnitImperial) {
                Text("lb").tag(true)
                Text("kg").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            OnboardingCaptionText(text: "A rough number is fine. You can refine this later.")
            Button("Continue") {
                if let value = Double(weightText) {
                    viewModel.weightValue = value
                }
                viewModel.goToBodyFatKnowledge()
            }
            .buttonStyle(PrimaryCTAButtonStyle())
        }
        .onAppear {
            weightText = String(format: viewModel.weightUnitImperial ? "%.0f" : "%.1f", viewModel.weightValue)
        }
        .onChange(of: viewModel.weightUnitImperial) { newValue in
            if newValue {
                viewModel.weightValue = viewModel.weightValue * 2.20462
            } else {
                viewModel.weightValue = viewModel.weightValue / 2.20462
            }
            weightText = String(format: newValue ? "%.0f" : "%.1f", viewModel.weightValue)
        }
    }
}

private struct BodyFatKnowledgeScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        OnboardingScreenContainer {
            OnboardingTitleText(text: "Do you know your body fat %?")
            VStack(spacing: 16) {
                Button {
                    viewModel.goToBodyFatNumeric()
                } label: {
                    OptionCard(title: "Yes, I know it", subtitle: "Enter the number", isSelected: false)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.goToBodyFatVisual()
                } label: {
                    OptionCard(title: "No, not really", subtitle: "We’ll estimate visually", isSelected: false)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct BodyFatNumericScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var value: String = ""

    var body: some View {
        OnboardingScreenContainer {
            OnboardingTitleText(text: "Enter your body fat %")
            TextField("Body fat %", text: $value)
                .keyboardType(.decimalPad)
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            OnboardingCaptionText(text: "If you have a DEXA scan, use that number. Otherwise use your best estimate.")
            Button("Continue") {
                viewModel.bodyFatPercentage = Double(value)
                viewModel.prepareScoreCalculation()
            }
            .buttonStyle(PrimaryCTAButtonStyle())
        }
        .onAppear {
            value = viewModel.bodyFatPercentage.map { String($0) } ?? ""
        }
    }
}

private struct BodyFatVisualScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        OnboardingScreenContainer {
            OnboardingTitleText(text: "Which of these looks most like you?")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(viewModel.visualOptions) { option in
                    Button {
                        viewModel.selectedVisualEstimate = option
                    } label: {
                        OptionCard(title: option.title, subtitle: option.rangeLabel, isSelected: viewModel.selectedVisualEstimate == option)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Continue") {
                viewModel.prepareScoreCalculation()
            }
            .buttonStyle(PrimaryCTAButtonStyle())
        }
    }
}

private struct LoadingScreen: View {
    var body: some View {
        LoadingStatusView(
            title: "Calculating your Body Score…",
            statusMessages: [
                "Analyzing leanness…",
                "Estimating muscularity (FFMI)…",
                "Checking aesthetics vs ideal…"
            ]
        )
    }
}

private struct BodyScoreRevealScreen: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        OnboardingScreenContainer {
            if let result = viewModel.bodyScoreResult {
                VStack(alignment: .leading, spacing: 24) {
                    OnboardingTitleText(text: "Your Body Score")
                    Text(result.scoreDisplay)
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                    Text(result.tagline)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("You’re leaner than about \(result.leanPercentile)% of people your age and sex.")
                        Text("Your muscle level (FFMI) is \(result.ffmiStatus).")
                        Text("Getting to around \(result.targetBodyFatRange) would put you in “\(result.targetLabel)” territory for your frame.")
                    }
                    Button("Build my Body HUD") {
                        viewModel.prepareAccountCreation()
                    }
                    .buttonStyle(PrimaryCTAButtonStyle())

                    Button("Email me my full body report") {
                        viewModel.showEmailSheet = true
                    }
                    .buttonStyle(SecondaryCTAButtonStyle())

                    ShareLink(item: viewModel.shareText) {
                        Text("Share my score")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct AccountCreationScreen: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        OnboardingScreenContainer {
            OnboardingTitleText(text: "Save your Body Score")
            OnboardingSubtitleText(text: "Create an account to save your score and build your live body HUD.")
            VStack(alignment: .leading, spacing: 12) {
                BulletRow(symbol: "chart.xyaxis.line", text: "Track your score over time")
                BulletRow(symbol: "sparkles", text: "Get a daily HUD and projections")
                BulletRow(symbol: "waveform.path.ecg", text: "Sync with DEXA scans and progress photos")
            }
            VStack(spacing: 12) {
                Button("Continue with Apple") {
                    Task { await authManager.handleAppleSignIn() }
                }
                .buttonStyle(PrimaryCTAButtonStyle())
                Button("Continue with Google") {
                    // Placeholder until Google auth lands
                }
                .buttonStyle(SecondaryCTAButtonStyle())
            }
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                SecureField("Password", text: $password)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                TextField("Name (optional)", text: $name)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button(isSubmitting ? "Creating…" : "Use email") {
                    Task { await createAccount() }
                }
                .buttonStyle(PrimaryCTAButtonStyle())
                .disabled(isSubmitting)
            }
        }
    }

    private func createAccount() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Enter email and password"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await authManager.signUp(email: email, password: password, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EmailCaptureSheet: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Email your report")
                .font(.title2).bold()
            Text("We’ll send you your Body Score, what it means, and a link to build your HUD later.")
                .font(.body)
                .foregroundStyle(.secondary)
            TextField("Email address", text: $viewModel.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button(viewModel.isSendingEmail ? "Sending…" : "Send my report") {
                Task {
                    await viewModel.sendEmailReport()
                }
            }
            .buttonStyle(PrimaryCTAButtonStyle())
            .disabled(viewModel.isSendingEmail)
            if viewModel.emailSent {
                Text("Report sent! Check your inbox.")
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .onDisappear { viewModel.resetEmailState() }
    }
}
