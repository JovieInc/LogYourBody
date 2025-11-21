import SwiftUI

struct BodyScoreHeightView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var centimetersFocused: Bool
    @State private var heightError: String?

    var body: some View {
        OnboardingPageTemplate(
            title: "How tall are you?",
            subtitle: "Height helps us normalize your Body Score.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .height),
            content: {
                VStack(spacing: 28) {
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
                Button("Continue") {
                    viewModel.persistHeightEntry()
                    viewModel.goToNextStep()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueHeight)
                .opacity(continueButtonOpacity)
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
    }

    private var heightUnitBinding: Binding<HeightUnit> {
        Binding<HeightUnit>(
            get: { viewModel.heightUnit },
            set: { viewModel.setHeightUnit($0) }
        )
    }

    private var continueButtonOpacity: Double {
        viewModel.canContinueHeight ? 1 : 0.4
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
                .foregroundStyle(Color.appTextSecondary)

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
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.appCard.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(centimetersFocused ? Color.appPrimary : Color.appBorder.opacity(0.5))
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.centimetersFocused = true
                }
            }

            if let error = heightError {
                Text(error)
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(Color.red)
            } else {
                Text("Most adults fall between 100–250 cm.")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(Color.appTextTertiary)
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
                .onChange(of: viewModel.heightFeet) { _ in
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
                .onChange(of: viewModel.heightInches) { _ in
                    HapticManager.shared.selection()
                }
            }
            .frame(height: 160)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.appCard.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.appBorder.opacity(0.5))
            )

            Text("We’ll convert everything into centimeters automatically.")
                .font(OnboardingTypography.caption)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var helperCard: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Why we ask")
                    .font(OnboardingTypography.headline)
                    .foregroundStyle(Color.appText)

                Text("Height anchors lean mass so taller frames stay comparable.")
                    .font(OnboardingTypography.body)
                    .foregroundStyle(Color.appTextSecondary)

                FFMIInfoLink()
                    .padding(.top, 4)
            }
        }
    }
}

#Preview {
    BodyScoreHeightView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
