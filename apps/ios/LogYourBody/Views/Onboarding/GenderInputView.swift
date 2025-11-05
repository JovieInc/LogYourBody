//
// GenderInputView.swift
// LogYourBody
//
import SwiftUI

struct GenderInputView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @State private var isEditing = false
    @State private var hasHealthKitData = false
    @Environment(\.colorScheme)
    var colorScheme    
    var body: some View {
        ZStack {
            // Edge-to-edge background
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
            // Header with Liquid Glass effect
            HStack {
                Button(
            action: {
                    viewModel.previousStep()
                    // HapticManager.shared.buttonTap()
                },
            label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Go back")
                        .accessibilityHint("Return to previous step")
                }
        )
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // Content with enhanced spacing for Liquid Glass
            ScrollView {
                VStack(spacing: 48) {
                    // Title section with Liquid Glass card
                    VStack(spacing: 16) {
                        Text("Your Biological Sex")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.appText)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Your biological sex")
                            .accessibilityHint("Select your biological sex for accurate FFMI calculations")
                        
                        Text("Used to calculate FFMI accurately")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.appTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    .padding(.horizontal, 24)
                    
                    // Show pre-populated data or options
                    if hasHealthKitData && !isEditing {
                        // Read-only summary view with Liquid Glass
                        VStack(spacing: 24) {
                            HStack {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Biological Sex")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.appTextSecondary)
                                    
                                    Text(viewModel.data.gender?.rawValue ?? "")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.appText)
                                }
                                
                                Spacer()
                                
                                Button(
            action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        isEditing = true
                                    }
                                    // HapticManager.shared.buttonTap()
                                },
            label: {
                                    Text("Edit")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.appPrimary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(.ultraThinMaterial)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(Color.appPrimary.opacity(0.1))
                                                )
                                        )
                                }
        )
                                .accessibilityLabel("Edit")
                                .accessibilityHint("Change your biological sex selection")
                            }
                            .padding(24)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                            )
                        }
                        .padding(.horizontal, 24)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 1.1).combined(with: .opacity)
                        ))
                    } else {
                        // Gender options with enhanced Liquid Glass design
                        VStack(spacing: 16) {
                            ForEach(OnboardingData.Gender.allCases, id: \.self) { gender in
                                LiquidGlassGenderButton(
                                    gender: gender,
                                    isSelected: viewModel.data.gender == gender,
                                    action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            viewModel.data.gender = gender
                                            if hasHealthKitData && isEditing {
                                                isEditing = false
                                            }
                                        }
                                        // HapticManager.shared.buttonTap()
                                    }
                                )
                            }
                            
                            if hasHealthKitData && isEditing {
                                LiquidGlassSecondaryCTAButton(
                                    text: "Cancel",
                                    action: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                            isEditing = false
                                        }
                                    }
                                )
                                .padding(.top, 8)
                                .accessibilityLabel("Cancel")
                                .accessibilityHint("Keep current selection")
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Continue button with Liquid Glass
            VStack(spacing: 20) {
                LiquidGlassCTAButton(
                    text: "Continue",
                    icon: "arrow.right",
                    action: {
                        viewModel.nextStep()
                    },
                    isEnabled: viewModel.data.gender != nil
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.data.gender != nil)
                .accessibilityLabel("Continue")
                .accessibilityHint(viewModel.data.gender == nil ? "Select a gender to continue" : "Go to next step")
                .accessibilityAddTraits(viewModel.data.gender == nil ? .isButton : [])
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Check if we have HealthKit data
            hasHealthKitData = viewModel.data.healthKitEnabled && viewModel.data.gender != nil
        }
    }
}

struct LiquidGlassGenderButton: View {
    let gender: OnboardingData.Gender
    let isSelected: Bool
    let action: () -> Void
    
    private var icon: String {
        switch gender {
        case .male:
            return "figure.stand"
        case .female:
            return "figure.stand.dress"
        }
    }
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                // Icon with enhanced styling
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.appPrimary.opacity(0.15) : Color.clear)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(isSelected ? .appPrimary : .appTextSecondary)
                        .symbolRenderingMode(.hierarchical)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(gender.rawValue)
                        .font(.system(size: 19, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .appText : .appTextSecondary)
                    
                    if isSelected {
                        Text("Selected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.appPrimary)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.appPrimary)
                        .symbolRenderingMode(.hierarchical)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill((isSelected ? Color.appPrimary : Color.gray).opacity(isSelected ? 0.1 : 0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.appPrimary.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityLabel("\(gender.rawValue) gender option")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
struct GenderInputView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GenderInputView()
                .environmentObject(OnboardingViewModel())
                .preferredColorScheme(.light)
            
            GenderInputView()
                .environmentObject(OnboardingViewModel())
                .preferredColorScheme(.dark)
        }
    }
}
#endif
