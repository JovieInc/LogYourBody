//
// NameInputView.swift
// LogYourBody
//
import SwiftUI

struct NameInputView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @FocusState private var isNameFieldFocused: Bool
    @State private var animateTitle = false
    @State private var animateField = false
    
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
            ScrollView {
                VStack(spacing: 48) {
                    // Title section
                    VStack(spacing: 16) {
                        Text("What's Your Name?")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.appText)
                            .multilineTextAlignment(.center)
                            .opacity(animateTitle ? 1 : 0)
                            .offset(y: animateTitle ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animateTitle)
                    }
                    .padding(.top, 40)
                    .padding(.horizontal, 24)
                    
                    // Name input with Liquid Glass styling
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Full Name")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.appTextSecondary)
                            
                            TextField("Enter your name", text: $viewModel.data.name)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.appText)
                                .focused($isNameFieldFocused)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit {
                                    if !viewModel.data.name.isEmpty {
                                        viewModel.nextStep()
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .modifier(NameInputLiquidGlassFieldModifier(isFocused: isNameFieldFocused))
                        }
                    }
                    .padding(.horizontal, 24)
                    .opacity(animateField ? 1 : 0)
                    .offset(y: animateField ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: animateField)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isNameFieldFocused = false
            }
            
            Spacer()
            
            // Continue button with Liquid Glass
            VStack(spacing: 20) {
                LiquidGlassCTAButton(
                    text: "Continue",
                    icon: "arrow.right",
                    action: {
                        viewModel.nextStep()
                    },
                    isEnabled: !viewModel.data.name.isEmpty
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: !viewModel.data.name.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            }
        }
        .onAppear {
            animateTitle = true
            animateField = true
            
            // Auto-focus the text field after animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isNameFieldFocused = true
            }
        }
    }
}

// MARK: - Liquid Glass Field Modifier

struct NameInputLiquidGlassFieldModifier: ViewModifier {
    let isFocused: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill((isFocused ? Color.appPrimary : Color.gray).opacity(isFocused ? 0.1 : 0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isFocused ? Color.appPrimary.opacity(0.5) : Color.clear,
                            lineWidth: 2
                        )
                )
        } else {
            content
                .background(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isFocused ? Color.appPrimary : Color.appBorder, lineWidth: 1)
                )
                .cornerRadius(16)
        }
    }
}

#if DEBUG
struct NameInputView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NameInputView()
                .environmentObject(OnboardingViewModel())
                .preferredColorScheme(.light)
            
            NameInputView()
                .environmentObject(OnboardingViewModel())
                .preferredColorScheme(.dark)
        }
    }
}
#endif
