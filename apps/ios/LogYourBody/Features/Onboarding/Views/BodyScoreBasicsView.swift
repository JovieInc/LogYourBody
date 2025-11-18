import SwiftUI

struct BodyScoreBasicsView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    private var birthYearBinding: Binding<Int> {
        Binding<Int>(
            get: { viewModel.bodyScoreInput.birthYear ?? viewModel.defaultBirthYear },
            set: { viewModel.updateBirthYear($0) }
        )
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Let’s dial in basics.",
            subtitle: "Keep it simple—these power your Body Score.",
            onBack: { viewModel.goBack() }
        ) {
            VStack(spacing: 28) {
                OnboardingFormSection(title: "Biological Sex", caption: "Used to set accurate FFMI and body-fat bands.") {
                    VStack(spacing: 16) {
                        ForEach(BiologicalSex.allCases, id: \.self) { sex in
                            OnboardingOptionButton(
                                title: sex.description,
                                subtitle: nil,
                                isSelected: viewModel.bodyScoreInput.sex == sex,
                                action: {
                                    viewModel.updateSex(sex)
                                }
                            )
                        }
                    }
                }

                OnboardingFormSection(title: "Birth Year", caption: "We use age ranges to benchmark your metrics.") {
                    VStack(spacing: 16) {
                        Picker("Birth Year", selection: birthYearBinding) {
                            ForEach(viewModel.birthYearOptions, id: \.self) { year in
                                Text("\(year)").tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                    }
                }
            }
        } footer: {
            VStack(spacing: 12) {
                Button("Continue") {
                    viewModel.goToNextStep()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueBasics)
                .opacity(viewModel.canContinueBasics ? 1 : 0.4)

                Button("Back") {
                    viewModel.goBack()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
        .onAppear {
            if viewModel.bodyScoreInput.birthYear == nil {
                viewModel.updateBirthYear(viewModel.defaultBirthYear)
            }
        }
    }
}

#Preview {
    BodyScoreBasicsView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
