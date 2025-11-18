//
// HealthDisclaimerView.swift
// LogYourBody
//
import SwiftUI
struct HealthDisclaimerView: View {
    @Environment(\.dismiss)
    private var dismiss
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Section
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                            .padding(.top, 20)

                        Text("Health & Medical Disclaimer")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)

                        Text("Please read this important information")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)

                    // Disclaimer Content
                    VStack(alignment: .leading, spacing: 20) {
                        DisclaimerSection(
                            title: "Not Medical Advice",
                            content: "LogYourBody is a fitness tracking application designed for informational and educational purposes only. The information provided by this app does not constitute medical advice and should not be used as a substitute for professional medical advice, diagnosis, or treatment."
                        )

                        DisclaimerSection(
                            title: "Consult Healthcare Professionals",
                            content: "Always seek the advice of your physician or other qualified health provider with any questions you may have regarding a medical condition, diet, exercise routine, or before making any changes to your health regimen. Never disregard professional medical advice or delay in seeking it because of something you have read or seen in this app."
                        )

                        DisclaimerSection(
                            title: "Body Composition Estimates",
                            content: "Body fat percentage, FFMI, and other body composition metrics provided by this app are estimates based on formulas and algorithms. These estimates may not be accurate for all individuals and should not be used as the sole basis for health decisions. For accurate body composition analysis, consult with healthcare professionals who can perform clinical assessments."
                        )

                        DisclaimerSection(
                            title: "Physical Activity",
                            content: "Before beginning any exercise program, consult with your healthcare provider, especially if you have any pre-existing health conditions, injuries, or concerns. The app's tracking features are not a substitute for professional fitness guidance."
                        )

                        DisclaimerSection(
                            title: "Emergency Situations",
                            content: "In case of a medical emergency, call your local emergency services immediately. Do not rely on this app for emergency medical situations."
                        )

                        DisclaimerSection(
                            title: "Individual Results",
                            content: "Individual results may vary. The app tracks your personal data and progress, but cannot guarantee specific outcomes. Your results will depend on various factors including genetics, adherence to nutrition and exercise plans, and overall health status."
                        )

                        DisclaimerSection(
                            title: "Data Accuracy",
                            content: "While we strive to ensure the accuracy of calculations and data processing, we cannot guarantee that all information is error-free. Users should verify important health metrics with appropriate medical devices and professionals."
                        )

                        DisclaimerSection(
                            title: "Age Restrictions",
                            content: "This app is intended for users aged 17 and older. Minors should use this app only under adult supervision and with appropriate medical guidance."
                        )

                        // Acknowledgment
                        VStack(spacing: 16) {
                            Text("By using LogYourBody, you acknowledge that you have read and understood this disclaimer and agree to use the app at your own risk.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)

                            Text("Last updated: \(Date(), style: .date)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Health Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.medium)
            }
        }
    }
}

struct DisclaimerSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Text(content)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        HealthDisclaimerView()
    }
    .preferredColorScheme(.dark)
}
