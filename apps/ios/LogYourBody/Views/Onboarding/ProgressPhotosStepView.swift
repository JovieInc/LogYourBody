//
// ProgressPhotosStepView.swift
// LogYourBody
//
import SwiftUI
import PhotosUI

struct ProgressPhotosStepView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var animateTitle = false
    @State private var animateContent = false
    @State private var animateButton = false
    @StateObject private var uploadService = BackgroundPhotoUploadService.shared
    @StateObject private var processingService = ImageProcessingService.shared
    @EnvironmentObject var authManager: AuthManager

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
                            HapticManager.shared.buttonTap()
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
                        // Title section with animation
                        VStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.9))
                                .opacity(animateTitle ? 1 : 0)
                                .scaleEffect(animateTitle ? 1 : 0.8)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animateTitle)

                            Text("Add Progress Photos")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.appText)
                                .multilineTextAlignment(.center)
                                .opacity(animateTitle ? 1 : 0)
                                .offset(y: animateTitle ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: animateTitle)

                            Text("Track your transformation with visual progress")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .opacity(animateTitle ? 1 : 0)
                                .offset(y: animateTitle ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: animateTitle)
                        }
                        .padding(.top, 40)

                        // Photo selection area
                        VStack(spacing: 24) {
                            if selectedPhotos.isEmpty {
                                // Initial photo picker
                                PhotosPicker(
                                    selection: $selectedPhotos,
                                    maxSelectionCount: 50,
                                    matching: .images
                                ) {
                                    VStack(spacing: 16) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white.opacity(0.1))
                                                .frame(width: 80, height: 80)

                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 36))
                                                .foregroundColor(.white)
                                        }

                                        Text("Select Photos")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundColor(.white)

                                        Text("Choose multiple photos at once")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(.appTextSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .modifier(LiquidGlassPhotoPickerModifier())
                                }
                                .opacity(animateContent ? 1 : 0)
                                .scaleEffect(animateContent ? 1 : 0.9)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: animateContent)
                            } else if uploadService.totalCount > 0 {
                                // Upload queued state
                                VStack(spacing: 20) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.green)

                                        Text("\(selectedPhotos.count) photos queued")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.appText)
                                    }

                                    Text("Photos will upload in the background")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(.appTextSecondary)
                                        .multilineTextAlignment(.center)

                                    PhotosPicker(
                                        selection: $selectedPhotos,
                                        maxSelectionCount: 50,
                                        matching: .images
                                    ) {
                                        Text("Change Selection")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.appPrimary)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .modifier(LiquidGlassButtonModifier())
                                    }
                                }
                                .padding(24)
                                .modifier(LiquidGlassCardModifier())
                                .transition(.scale.combined(with: .opacity))
                            } else {
                                // Selected photos state
                                VStack(spacing: 20) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "photo.stack.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.appPrimary)

                                        Text("\(selectedPhotos.count) photos selected")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.appText)
                                    }

                                    Text("Photos will be dated automatically")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(.appTextSecondary)

                                    PhotosPicker(
                                        selection: $selectedPhotos,
                                        maxSelectionCount: 50,
                                        matching: .images
                                    ) {
                                        Text("Change Selection")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.appPrimary)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .modifier(LiquidGlassButtonModifier())
                                    }
                                }
                                .padding(24)
                                .modifier(LiquidGlassCardModifier())
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 24)
                        .onChange(of: selectedPhotos) { _, newValue in
                            if !newValue.isEmpty {
                                HapticManager.shared.successAction()
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                Spacer()

                // Bottom buttons with Liquid Glass
                VStack(spacing: 20) {
                    if selectedPhotos.isEmpty {
                        LiquidGlassSecondaryCTAButton(
                            text: "Skip for Now",
                            action: handleContinue
                        )
                        .opacity(animateButton ? 1 : 0)
                        .offset(y: animateButton ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: animateButton)
                    } else {
                        LiquidGlassCTAButton(
                            text: "Continue",
                            icon: "arrow.right",
                            action: handleContinue,
                            isEnabled: true
                        )
                        .opacity(animateButton ? 1 : 0)
                        .offset(y: animateButton ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: animateButton)
                    }

                    if selectedPhotos.isEmpty {
                        Text("You can add photos anytime from the dashboard")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.appTextTertiary)
                            .multilineTextAlignment(.center)
                            .opacity(animateButton ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: animateButton)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            animateTitle = true
            animateContent = true
            animateButton = true
        }
    }

    private func handleContinue() {
        HapticManager.shared.buttonTap()

        if !selectedPhotos.isEmpty {
            // Queue photos for background upload
            Task {
                await uploadService.queuePhotosForUpload(selectedPhotos)
                viewModel.data.hasUploadedPhotos = true
            }
        }

        viewModel.nextStep()
    }
}

// MARK: - Liquid Glass Modifiers

struct LiquidGlassPhotoPickerModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.appCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                )
        }
    }
}

struct LiquidGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.appPrimary.opacity(0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.appPrimary.opacity(0.2), lineWidth: 1)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                )
        }
    }
}

#if DEBUG
struct ProgressPhotosStepView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ProgressPhotosStepView()
                .environmentObject(OnboardingViewModel())
                .environmentObject(AuthManager.shared)
                .preferredColorScheme(.dark)
        }
    }
}
#endif
