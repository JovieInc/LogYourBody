//
// HealthDisclaimerView.swift
// LogYourBody
//
import SwiftUI

struct HealthDisclaimerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.jovieCanvas
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
                    header

                    VStack(alignment: .leading, spacing: 24) {
                        DisclaimerSection(
                            title: "General Information",
                            content: """
                            LogYourBody is a fitness tracking application designed for informational and
                            educational purposes only. The information provided by this app does not constitute
                            medical advice and should not be used as a substitute for professional medical advice,
                            diagnosis, or treatment.
                            """
                        )

                        DisclaimerSection(
                            title: "Consult Healthcare Professionals",
                            content: """
                            Always seek the advice of your physician or other qualified health provider with any
                            questions you may have regarding a medical condition, diet, exercise routine, or before
                            making any changes to your health regimen. Never disregard professional medical advice or
                            delay in seeking it because of something you have read or seen in this app.
                            """
                        )

                        DisclaimerSection(
                            title: "Body Composition Estimates",
                            content: """
                            Body fat percentage, FFMI, and other body composition metrics provided by this app are
                            estimates based on formulas and algorithms. These estimates may not be accurate for all
                            individuals and should not be used as the sole basis for health decisions. For accurate
                            body composition analysis, consult with healthcare professionals who can perform clinical
                            assessments.
                            """
                        )

                        DisclaimerSection(
                            title: "Physical Activity",
                            content: """
                            Before beginning any exercise program, consult with your healthcare provider, especially
                            if you have any pre-existing health conditions, injuries, or concerns. The app's tracking
                            features are not a substitute for professional fitness guidance.
                            """
                        )

                        DisclaimerSection(
                            title: "Emergency Situations",
                            content: """
                            In case of a medical emergency, call your local emergency services immediately.
                            Do not rely on this app for emergency medical situations.
                            """,
                            emphasis: .emergency
                        )

                        DisclaimerSection(
                            title: "Individual Results",
                            content: """
                            Individual results may vary. The app tracks your personal data and progress, but cannot
                            guarantee specific outcomes. Your results will depend on various factors including
                            genetics, adherence to nutrition and exercise plans, and overall health status.
                            """
                        )

                        DisclaimerSection(
                            title: "Data Accuracy",
                            content: """
                            While we strive to ensure the accuracy of calculations and data processing, we cannot
                            guarantee that all information is error-free. Users should verify important health metrics
                            with appropriate medical devices and professionals.
                            """
                        )

                        DisclaimerSection(
                            title: "Age Restrictions",
                            content: """
                            This app is intended for users aged 17 and older.
                            Minors should use this app only under adult supervision and with appropriate medical guidance.
                            """
                        )

                        acknowledgment
                    }
                    .padding(JovieTokens.screenInset)
                    .systemBGlassSurface(
                        cornerRadius: JovieTokens.cardRadius,
                        tint: .jovieText,
                        tintOpacity: 0.045,
                        borderColor: .jovieHairline,
                        borderOpacity: 0.9
                    )
                }
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.top, JovieTokens.sectionGap)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Health Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .accessibilityLabel("Done")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Important health information", systemImage: "cross.case.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.warning)

            Text("Health & Medical Disclaimer")
                .font(.title2.weight(.bold))
                .foregroundColor(.jovieText)

            Text("Please read this information before relying on LogYourBody data.")
                .font(.body)
                .foregroundColor(.jovieTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var acknowledgment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                """
                By using LogYourBody, you acknowledge that you have read and understood this disclaimer
                and agree to use the app at your own risk.
                """
            )
            .font(.subheadline.weight(.medium))
            .foregroundColor(.jovieText)
            .fixedSize(horizontal: false, vertical: true)

            Text("Last updated: \(Date(), style: .date)")
                .font(.footnote)
                .foregroundColor(.jovieTextSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                .fill(Color.jovieSurfaceElevated)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct DisclaimerSection: View {
    enum Emphasis: Equatable {
        case standard
        case emergency
    }

    let title: String
    let content: String
    var emphasis: Emphasis = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if emphasis == .emergency {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(.jovieText)
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.jovieText)
            }

            Text(content)
                .font(.body)
                .foregroundColor(.jovieTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        HealthDisclaimerView()
    }
    .preferredColorScheme(.dark)
}
