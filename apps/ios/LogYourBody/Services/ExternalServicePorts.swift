//
// ExternalServicePorts.swift
// LogYourBody
//
// App-owned ports and thin adapters for platform SDK boundaries.
//

import AVFoundation
import AuthenticationServices
import Foundation
import LocalAuthentication
import Photos
import PhotosUI
import SwiftUI
import UIKit

protocol Glp1RemoteDataProviding {
    func fetchGlp1Medications(userId: String) async throws -> [Glp1Medication]
    func fetchGlp1DoseLogs(userId: String, limit: Int) async throws -> [Glp1DoseLog]
}

extension Glp1RemoteDataProviding {
    func fetchGlp1DoseLogs(userId: String) async throws -> [Glp1DoseLog] {
        try await fetchGlp1DoseLogs(userId: userId, limit: 100)
    }
}

protocol DexaResultRemoteDataProviding {
    func fetchDexaResults(userId: String, limit: Int) async throws -> [DexaResult]
}

protocol AnalyticsTracking {
    func start()
    func identify(userId: String?, properties: [String: String]?)
    func track(event: String, properties: [String: String]?)
    func reset()
    func isFeatureEnabled(flagKey: String) -> Bool
}

extension AnalyticsTracking {
    func identify(userId: String?) {
        identify(userId: userId, properties: nil)
    }

    func track(event: String) {
        track(event: event, properties: nil)
    }
}

protocol ErrorTrackingStarting {
    func start()
}

@MainActor
enum AppServicePorts {
    static var glp1RemoteDataProvider: Glp1RemoteDataProviding {
        SupabaseManager.shared
    }

    static var dexaResultRemoteDataProvider: DexaResultRemoteDataProviding {
        SupabaseManager.shared
    }

    static var analyticsTracker: AnalyticsTracking {
        AnalyticsService.shared
    }

    static var errorTracker: ErrorTrackingStarting {
        ErrorTrackingService.shared
    }
}

extension SupabaseManager: Glp1RemoteDataProviding, DexaResultRemoteDataProviding {}
extension AnalyticsService: AnalyticsTracking {}
extension ErrorTrackingService: ErrorTrackingStarting {}

enum AppAuthorizationState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown
}

enum AppBiometryType: Equatable {
    case none
    case faceID
    case touchID

    var authViewType: BiometricAuthView.BiometricType {
        switch self {
        case .touchID:
            return .touchID
        case .none, .faceID:
            return .faceID
        }
    }
}

enum BiometricAuthenticationResult: Equatable {
    case success
    case failure
    case unavailable
}

protocol BiometricAuthenticating: AnyObject {
    func availableBiometryType() -> AppBiometryType
    func authenticate(
        reason: String,
        cancelTitle: String?,
        fallbackTitle: String?,
        timeout: TimeInterval?
    ) async -> BiometricAuthenticationResult
    func cancelCurrentAuthentication()
}

final class LocalBiometricAuthenticationAdapter: BiometricAuthenticating {
    static let shared = LocalBiometricAuthenticationAdapter()

    private var currentContext: LAContext?

    func availableBiometryType() -> AppBiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    func authenticate(
        reason: String,
        cancelTitle: String? = nil,
        fallbackTitle: String? = "",
        timeout: TimeInterval? = nil
    ) async -> BiometricAuthenticationResult {
        let context = LAContext()
        context.localizedCancelTitle = cancelTitle
        context.localizedFallbackTitle = fallbackTitle ?? ""

        currentContext?.invalidate()
        currentContext = context

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            currentContext = nil
            return .unavailable
        }

        let timeoutTask: Task<Void, Never>?
        if let timeout {
            timeoutTask = Task { [weak self, weak context] in
                let nanoseconds = UInt64(timeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                if let context, self?.currentContext === context {
                    context.invalidate()
                }
            }
        } else {
            timeoutTask = nil
        }

        let success = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }

        timeoutTask?.cancel()
        if currentContext === context {
            currentContext = nil
        }

        return success ? .success : .failure
    }

    func cancelCurrentAuthentication() {
        currentContext?.invalidate()
        currentContext = nil
    }
}

struct AppPhotoAsset: Identifiable, Equatable {
    let id: String
    let data: Data
    let image: UIImage
    let localIdentifier: String?
}

struct AppPhotosPicker<Label: View>: View {
    private let maxSelectionCount: Int?
    private let onSelection: ([AppPhotoAsset]) async -> Void
    private let label: () -> Label

    @State private var selectedItems: [PhotosPickerItem] = []

    init(
        maxSelectionCount: Int? = nil,
        onSelection: @escaping ([AppPhotoAsset]) async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.maxSelectionCount = maxSelectionCount
        self.onSelection = onSelection
        self.label = label
    }

    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: maxSelectionCount,
            matching: .images
        ) {
            label()
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await loadSelection(newItems)
                await MainActor.run {
                    selectedItems = []
                }
            }
        }
    }

    private func loadSelection(_ items: [PhotosPickerItem]) async {
        var assets: [AppPhotoAsset] = []

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                continue
            }

            assets.append(
                AppPhotoAsset(
                    id: item.itemIdentifier ?? UUID().uuidString,
                    data: data,
                    image: image,
                    localIdentifier: item.itemIdentifier
                )
            )
        }

        await onSelection(assets)
    }
}

protocol PhotoLibraryManaging {
    func authorizationStatus() -> AppAuthorizationState
    func deleteAssets(localIdentifiers: [String]) async throws
    func saveImage(_ image: UIImage) async -> Bool
}

struct LivePhotoLibraryAdapter: PhotoLibraryManaging {
    static let shared = LivePhotoLibraryAdapter()

    func authorizationStatus() -> AppAuthorizationState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    func deleteAssets(localIdentifiers: [String]) async throws {
        guard !localIdentifiers.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard fetchResult.firstObject != nil else { return }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(fetchResult)
        }
    }

    func saveImage(_ image: UIImage) async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus()

        switch status {
        case .authorized, .limited:
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            return true
        case .notDetermined:
            let newStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { authStatus in
                    continuation.resume(returning: authStatus)
                }
            }

            switch newStatus {
            case .authorized, .limited:
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

protocol CameraAuthorizing {
    var isCameraAvailable: Bool { get }
    func authorizationStatus() -> AppAuthorizationState
    func requestAccess() async -> Bool
}

struct LiveCameraAuthorizationAdapter: CameraAuthorizing {
    static let shared = LiveCameraAuthorizationAdapter()

    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func authorizationStatus() -> AppAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

struct PlatformCameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss)
    private var dismiss

    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .front
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PlatformCameraCaptureView

        init(parent: PlatformCameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PlatformAppleSignInButton: UIViewRepresentable {
    @Environment(\.colorScheme)
    private var colorScheme

    let authManager: AuthManager

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: colorScheme == .dark ? .white : .black
        )
        button.cornerRadius = Constants.cornerRadius
        button.isEnabled = true
        button.isUserInteractionEnabled = true
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleAuthorizationAppleIDButtonPress),
            for: .touchUpInside
        )

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTapGesture)
        )
        button.addGestureRecognizer(tapGesture)

        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.removeTarget(nil, action: nil, for: .allEvents)
        uiView.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleAuthorizationAppleIDButtonPress),
            for: .touchUpInside
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: PlatformAppleSignInButton

        init(parent: PlatformAppleSignInButton) {
            self.parent = parent
        }

        @objc
        func handleAuthorizationAppleIDButtonPress() {
            performAppleSignIn()
        }

        @objc
        func handleTapGesture() {
            performAppleSignIn()
        }

        private func performAppleSignIn() {
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }

            if let windowScene = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .first as? UIWindowScene,
               let window = windowScene.windows.first {
                return window
            }

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                return UIWindow(windowScene: windowScene)
            }

            preconditionFailure("No window scene available for Apple Sign In")
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return
            }

            Task {
                do {
                    try await parent.authManager.signInWithAppleCredentials(appleIDCredential)
                } catch {}
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            guard let error = error as? ASAuthorizationError else {
                return
            }

            switch error.code {
            case .canceled:
                break
            case .failed:
                showErrorAlert("Apple Sign In failed. Please try again.")
            case .invalidResponse:
                showErrorAlert("Invalid response from Apple Sign In.")
            case .notHandled:
                showErrorAlert("Apple Sign In request was not handled.")
            case .notInteractive:
                showErrorAlert("Apple Sign In is not available right now. Please try again or use another sign-in method.")
            case .unknown:
                showErrorAlert("An unknown error occurred with Apple Sign In.")
            default:
                showErrorAlert("An error occurred with Apple Sign In.")
            }
        }

        private func showErrorAlert(_ message: String) {
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    let alert = UIAlertController(title: "Sign In Error", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    rootViewController.present(alert, animated: true)
                }
            }
        }
    }
}
