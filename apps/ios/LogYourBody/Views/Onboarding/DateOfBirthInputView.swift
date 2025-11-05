//
// DateOfBirthInputView.swift
// LogYourBody
//
import SwiftUI
struct DateOfBirthInputView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @State private var selectedDate = Date()
    @State private var isEditing = false
    @State private var hasHealthKitData = false
    @State private var showAgeWarning = false
    
    private var age: Int? {
        guard let dob = viewModel.data.dateOfBirth else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
        return ageComponents.year
    }
    
    private var isUnder17: Bool {
        guard let age = age else { return false }
        return age < 17
    }
    
    var body: some View {
        ZStack {
            // Edge-to-edge background
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
            // Header
            HStack {
                Button(
            action: {
                    viewModel.previousStep()
                    // HapticManager.shared.buttonTap() // TODO: Add HapticManager to Xcode project
                },
            label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
        )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // Content
            VStack(spacing: 40) {
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Your Date of Birth")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.appText)
                    
                    Text("Helps personalize your metrics")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                
                // Show pre-populated data or picker
                if hasHealthKitData && !isEditing {
                    // Read-only summary view
                    VStack(spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date of Birth")
                                    .font(.system(size: 14))
                                    .foregroundColor(.appTextSecondary)
                                
                                if let dob = viewModel.data.dateOfBirth, let age = age {
                                    Text(dateText(for: dob, age: age))
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.appText)
                                }
                            }
                            
                            Spacer()
                            
                            Button(
            action: {
                                withAnimation(.spring(response: 0.3)) {
                                    isEditing = true
                                }
                                // HapticManager.shared.buttonTap() // TODO: Add HapticManager to Xcode project
                            },
            label: {
                                Text("Edit")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.appPrimary)
                            }
        )
                        }
                        .padding(20)
                        .background(Color.appCard)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale))
                } else {
                    // Date picker for manual entry or editing
                    VStack(spacing: 16) {
                        DatePicker("", selection: Binding(
                            get: { viewModel.data.dateOfBirth ?? Date() },
                            set: {
                                viewModel.data.dateOfBirth = $0
                                // Check age after selection
                                if let newAge = calculateAge(from: $0), newAge < 17 {
                                    showAgeWarning = true
                                } else {
                                    showAgeWarning = false
                                }
                            }
                        ), in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxHeight: 200)
                        
                        if let age = age {
                            VStack(spacing: 8) {
                                Text("\(age) years old")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(isUnder17 ? .red : .appPrimary)
                                    .padding(.top, 8)
                                    .transition(.opacity)
                                
                                if isUnder17 {
                                    Text("You must be 17 or older to use LogYourBody")
                                        .font(.system(size: 14))
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                        .transition(.opacity)
                                }
                            }
                        }
                        
                        if hasHealthKitData && isEditing {
                            LiquidGlassSecondaryCTAButton(
                                text: "Cancel",
                                action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        isEditing = false
                                    }
                                }
                            )
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            
            Spacer()
            
            // Continue button
            VStack(spacing: 16) {
                LiquidGlassCTAButton(
                    text: "Continue",
                    icon: "arrow.right",
                    action: {
                        viewModel.nextStep()
                    },
                    isEnabled: viewModel.data.dateOfBirth != nil && !isUnder17
                )
                .animation(.easeOut(duration: 0.2), value: viewModel.data.dateOfBirth != nil)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Initialize with user's date if available
            if let dob = viewModel.data.dateOfBirth {
                selectedDate = dob
                // Check if this came from HealthKit (we have it pre-populated)
                hasHealthKitData = viewModel.data.healthKitEnabled
            } else {
                // Default to 25 years ago
                selectedDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
                viewModel.data.dateOfBirth = selectedDate
                hasHealthKitData = false
            }
        }
    }
    
    private func dateText(for date: Date, age: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return "\(formatter.string(from: date)) (\(age) y/o)"
    }
    
    private func calculateAge(from date: Date) -> Int? {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: date, to: Date())
        return ageComponents.year
    }
}

#Preview {
    DateOfBirthInputView()
        .environmentObject(OnboardingViewModel())
        .background(Color.appBackground)
}
