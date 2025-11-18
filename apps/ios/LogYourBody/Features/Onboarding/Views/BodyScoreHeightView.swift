import SwiftUI

struct BodyScoreHeightView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var centimetersFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "How tall are you?",
            subtitle: "Height helps us normalize lean mass and FFMI.",
            onBack: { viewModel.goBack() }
        ) {
            VStack(spacing: 28) {
                OnboardingSegmentedControl(options: HeightUnit.allCases, selection: heightUnitBinding)

                if viewModel.heightUnit == .centimeters {
                    centimetersInput
                } else {
                    imperialInput
                }

                helperCard
            }
        } footer: {
            Button("Continue") {
                viewModel.persistHeightEntry()
                viewModel.goToNextStep()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(!viewModel.canContinueHeight)
            .opacity(viewModel.canContinueHeight ? 1 : 0.4)
        }
    }

    private var heightUnitBinding: Binding<HeightUnit> {
        Binding<HeightUnit>(
            get: { viewModel.heightUnit },
            set: { viewModel.setHeightUnit($0) }
        )
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

                Text("Height anchors fat-free mass index (FFMI) and keeps comparisons fair across frames.")
                    .font(OnboardingTypography.body)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }
}

#Preview {
    BodyScoreHeightView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
