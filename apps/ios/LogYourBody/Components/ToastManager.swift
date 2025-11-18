//
// ToastManager.swift
// LogYourBody
//
import SwiftUI
import Combine
import UIKit

// MARK: - Toast Model
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval
    let hapticFeedback: Bool

    enum ToastType {
        case info
        case success
        case error
        case warning

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: return .appPrimary
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            }
        }
    }

    init(message: String, type: ToastType = .info, duration: TimeInterval = 3.0, hapticFeedback: Bool = true) {
        self.message = message
        self.type = type
        self.duration = duration
        self.hapticFeedback = hapticFeedback
    }
}

// MARK: - Toast Manager
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published private(set) var toasts: [Toast] = []
    @Published private(set) var currentToast: Toast?

    private var cancellables = Set<AnyCancellable>()
    private var toastTimer: Timer?

    private init() {
        // Process queue when toasts are added
        $toasts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] toasts in
                if self?.currentToast == nil && !toasts.isEmpty {
                    self?.showNextToast()
                }
            }
            .store(in: &cancellables)
    }

    func show(_ message: String, type: Toast.ToastType = .info, duration: TimeInterval = 3.0) {
        let toast = Toast(message: message, type: type, duration: duration)
        toasts.append(toast)

        // Haptic feedback
        if toast.hapticFeedback {
            switch type {
            case .success:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            case .error:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            case .warning:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            case .info:
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
    }

    private func showNextToast() {
        guard !toasts.isEmpty else { return }

        let toast = toasts.removeFirst()

        // Use async animation to not block UI
        Task { @MainActor in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentToast = toast
            }
        }

        // Auto dismiss using async Task instead of Timer
        toastTimer?.invalidate()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            dismissCurrentToast()
        }
    }

    func dismissCurrentToast() {
        toastTimer?.invalidate()

        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
            currentToast = nil
        }

        // Show next toast after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showNextToast()
        }
    }
}

// MARK: - Toast View
struct ToastView: View {
    let toast: Toast
    @Namespace private var namespace
    @State private var isShowing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 20))
                .foregroundColor(toast.type.color)
                .matchedGeometryEffect(id: "icon", in: namespace)

            Text(toast.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.appText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(isShowing ? 1 : 0.8)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isShowing = true
            }
        }
    }
}

// MARK: - Toast Container View
struct ToastContainerView: View {
    @ObservedObject private var toastManager = ToastManager.shared
    @Namespace private var namespace

    var body: some View {
        GeometryReader { _ in
            if let toast = toastManager.currentToast {
                VStack {
                    ToastView(toast: toast)
                        .matchedGeometryEffect(id: toast.id, in: namespace)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .zIndex(1_000)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .onTapGesture {
                            toastManager.dismissCurrentToast()
                        }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(toastManager.currentToast != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastManager.currentToast?.id)
    }
}

// MARK: - View Extension
extension View {
    func toastPresenter() -> some View {
        ZStack {
            self
            ToastContainerView()
        }
    }
}
