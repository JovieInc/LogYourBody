import SwiftUI

struct BodyScoreHeightView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var centimetersFocused: Bool
    @AccessibilityFocusState private var heightErrorFocused: Bool
    @State private var heightError: String?
    @State private var showWhyWeAsk = false

    var body: some View {
        OnboardingPageTemplate(
            title: "How tall are you?",
            subtitle: "Height helps us normalize your Body Score.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .height),
            content: {
                VStack(spacing: 24) {
                    OnboardingSegmentedControl(options: HeightUnit.allCases, selection: heightUnitBinding)

                    if viewModel.heightUnit == .centimeters {
                        centimetersInput
                    } else {
                        imperialInput
                    }

                    helperCard
                }
            },
            footer: {
                Button {
                    viewModel.persistHeightEntry()
                    viewModel.goToNextStep()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueHeight)
            }
        )
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        centimetersFocused = false
                    }
                }
            }
        }
        .onChange(of: heightError) { _, error in
            heightErrorFocused = error != nil
        }
    }

    private var heightUnitBinding: Binding<HeightUnit> {
        Binding<HeightUnit>(
            get: { viewModel.heightUnit },
            set: { viewModel.setHeightUnit($0) }
        )
    }

    private func validateHeightCentimeters(_ value: String) {
        guard !value.isEmpty else {
            heightError = nil
            return
        }

        let numeric = Double(value) ?? 0
        if numeric < 100 {
            heightError = "Enter at least 100 cm."
        } else {
            heightError = nil
        }
    }

    private var centimetersInput: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter centimeters")
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            TextField("175", text: Binding(
                get: { viewModel.heightCentimetersText },
                set: { viewModel.updateHeightCentimetersText($0) }
            ))
            .keyboardType(.decimalPad)
            .focused($centimetersFocused)
            .submitLabel(.done)
            .onSubmit {
                centimetersFocused = false
            }
            .onChange(of: viewModel.heightCentimetersText) { _, newValue in
                validateHeightCentimeters(newValue)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: JovieTokens.controlHeight)
            .systemBGlassSurface(
                cornerRadius: theme.radius.input,
                tint: centimetersFocused ? theme.colors.primary : theme.colors.text,
                tintOpacity: centimetersFocused ? 0.07 : 0.03,
                borderColor: centimetersFocused ? theme.colors.primary : theme.colors.border,
                borderOpacity: centimetersFocused ? 0.9 : 0.65
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.centimetersFocused = true
                }
            }
            .accessibilityLabel("Height in centimeters")
            .accessibilityHint("Enter a height between 100 and 250 centimeters.")

            if let error = heightError {
                Text(error)
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(theme.colors.error)
                    .accessibilityFocused($heightErrorFocused)
                    .accessibilityAddTraits(.isStaticText)
            } else {
                Text("Most adults fall between 100–250 cm.")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }

    private var imperialInput: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Picker("Feet", selection: Binding(
                    get: { viewModel.heightFeet },
                    set: { viewModel.heightFeet = $0 }
                )) {
                    ForEach(3...8, id: \.self) { value in
                        Text("\(value) ft").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .onChange(of: viewModel.heightFeet) { _, _ in
                    HapticManager.shared.selection()
                }

                Picker("Inches", selection: Binding(
                    get: { viewModel.heightInches },
                    set: { viewModel.heightInches = $0 }
                )) {
                    ForEach(0...11, id: \.self) { value in
                        Text("\(value) in").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .onChange(of: viewModel.heightInches) { _, _ in
                    HapticManager.shared.selection()
                }
            }
            .frame(height: 160)
            .systemBGlassSurface(
                cornerRadius: 20,
                tint: theme.colors.text,
                tintOpacity: 0.03,
                borderColor: theme.colors.border,
                borderOpacity: 0.65
            )

            Text("We’ll convert everything into centimeters automatically.")
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleWhyWeAsk()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(.footnote, design: .default).weight(.semibold))
                    Text("Why we ask")
                        .font(OnboardingTypography.caption)
                }
                .foregroundStyle(theme.colors.primary)
            }
            .buttonStyle(.plain)
            .jovieTouchTarget()
            .accessibilityValue(showWhyWeAsk ? "Expanded" : "Collapsed")

            if showWhyWeAsk {
                VStack(alignment: .leading, spacing: 8) {
                        Text("Height anchors lean mass so taller frames stay comparable.")
                            .font(OnboardingTypography.body)
                            .foregroundStyle(theme.colors.textSecondary)

                    FFMIInfoLink()
                        .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleWhyWeAsk() {
        if reduceMotion {
            showWhyWeAsk.toggle()
        } else {
            withAnimation(theme.animation.fast) {
                showWhyWeAsk.toggle()
            }
        }
    }
}

#Preview {
    BodyScoreHeightView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
