//
// EnhancedOTPInputView.swift
// LogYourBody
//
import SwiftUI
import UIKit
import Combine

struct EnhancedOTPInputView: View {
    @Binding var otpCode: String
    var numberOfDigits: Int = 6
    var onComplete: (() -> Void)?
    @Binding var errorMessage: String?
    @Binding var isLoading: Bool

    @State private var digits: [String] = []
    @FocusState private var focusedIndex: Int?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var lastPasteTime: Date?
    @State private var showPasteButton = false
    @State private var clipboardCode: String?
    @State private var isVerifying = false
    @State private var showError = false
    @State private var showSuccess = false

    // Animation states
    @State private var digitScales: [CGFloat] = []
    @State private var digitColors: [Color] = []
    @State private var shakeOffset: CGFloat = 0

    // Accessibility
    @AccessibilityFocusState private var accessibilityFocused: Bool

    init(otpCode: Binding<String>,
         numberOfDigits: Int = 6,
         errorMessage: Binding<String?>,
         isLoading: Binding<Bool>,
         onComplete: (() -> Void)? = nil) {
        self._otpCode = otpCode
        self.numberOfDigits = numberOfDigits
        self._errorMessage = errorMessage
        self._isLoading = isLoading
        self.onComplete = onComplete

        // Initialize state arrays
        _digits = State(initialValue: Array(repeating: "", count: numberOfDigits))
        _digitScales = State(initialValue: Array(repeating: 1.0, count: numberOfDigits))
        _digitColors = State(initialValue: Array(repeating: Color.appBorder, count: numberOfDigits))
    }

    // MARK: - Computed Views

    private var otpInputFields: some View {
        HStack(spacing: 8) {
            ForEach(0..<numberOfDigits, id: \.self) { index in
                digitInput(at: index)
            }
        }
        .offset(x: shakeOffset)
        .animation(.default, value: shakeOffset)
    }

    private func digitInput(at index: Int) -> some View {
        EnhancedDigitInput(
            digit: $digits[index],
            isFocused: focusedIndex == index,
            scale: digitScales[index],
            borderColor: digitColors[index],
            index: index,
            totalDigits: numberOfDigits,
            onTextChange: { newValue in
                handleTextChange(at: index, newValue: newValue)
            }
        )
        .focused($focusedIndex, equals: index)
        .scaleEffect(digitScales[index])
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: digitScales[index])
        .onTapGesture {
            focusedIndex = index
        }
        .accessibilityLabel("Digit \(index + 1) of \(numberOfDigits)")
        .accessibilityValue(digits[index].isEmpty ? "empty" : "filled")
        .accessibilityHint("Double tap to edit")
    }

    var body: some View {
        VStack(spacing: 16) {
            // OTP Input Fields
            otpInputFields

            // Paste Button (appears when clipboard has valid code)
            if showPasteButton, let code = clipboardCode {
                Button(
                    action: { pasteCode(code) },
                    label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 14))
                            Text("Paste code")
                                .font(.appBodySmall)
                        }
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.appPrimary.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.appPrimary.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                )
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Paste verification code from clipboard")
            }

            // Error State
            if showError, let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                    Text(error)
                        .font(.appCaption)
                }
                .foregroundColor(.error)
                .transition(.scale.combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }

            // Success State
            if showSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Code verified!")
                        .font(.appCaption)
                }
                .foregroundColor(.success)
                .transition(.scale.combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onAppear {
            setupView()
        }
        .onChange(of: digits) { _, _ in
            handleDigitsChange()
        }
        .onChange(of: errorMessage) { _, newError in
            if newError != nil {
                showErrorAnimation()
            } else {
                showError = false
            }
        }
        .onChange(of: isLoading) { _, loading in
            if loading {
                showVerifyingAnimation()
            } else if !showError {
                // Check if verification was successful
                if digits.allSatisfy({ !$0.isEmpty }) && errorMessage == nil {
                    showSuccessAnimation()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            checkClipboard()
        }
    }

    private func setupView() {
        // Initialize arrays if needed
        if digits.count != numberOfDigits {
            digits = Array(repeating: "", count: numberOfDigits)
            digitScales = Array(repeating: 1.0, count: numberOfDigits)
            digitColors = Array(repeating: Color.appBorder, count: numberOfDigits)
        }

        // Focus first field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            focusedIndex = 0
            accessibilityFocused = true
        }

        // Check clipboard on load
        checkClipboard()
    }

    private func handleTextChange(at index: Int, newValue: String) {
        // Prevent recursive updates
        guard newValue != digits[index] else { return }

        // Clear error on new input
        errorMessage = nil
        showError = false

        // Handle deletion
        if newValue.isEmpty {
            digits[index] = ""
            animateDigit(at: index, scale: 0.9)

            // Move focus to previous field if available
            if index > 0 {
                DispatchQueue.main.async {
                    self.focusedIndex = index - 1
                }
            }
            return
        }

        // Handle multi-character paste
        if newValue.count > 1 {
            handlePastedCode(newValue)
            return
        }

        // Handle single digit
        if newValue.count == 1 && newValue.last!.isNumber {
            digits[index] = String(newValue.last!)
            animateDigit(at: index, scale: 1.1)

            // Move to next field with delay to prevent UI freeze
            DispatchQueue.main.async {
                if index < self.numberOfDigits - 1 {
                    self.focusedIndex = index + 1
                } else {
                    // Last digit entered
                    self.focusedIndex = nil
                }
            }
        }
    }

    private func handleDigitsChange() {
        // Update the bound otpCode
        otpCode = digits.joined()

        // Check if all digits are filled
        if digits.count == numberOfDigits && digits.allSatisfy({ !$0.isEmpty }) {
            // Announce to accessibility
            UIAccessibility.post(notification: .announcement,
                                 argument: "Code entered, verifying")

            // Call completion handler
            onComplete?()
        }
    }

    private func checkClipboard() {
        guard let clipboardString = UIPasteboard.general.string else {
            showPasteButton = false
            return
        }

        // Extract numbers from clipboard
        let numbers = clipboardString.filter { $0.isNumber }

        // Check if it's a valid OTP code
        if numbers.count == numberOfDigits {
            clipboardCode = numbers

            // Only show paste button if clipboard changed recently (within 3 seconds)
            if let changeTime = UIPasteboard.general.changeCount.description.data(using: .utf8),
               let lastChange = try? JSONDecoder().decode(Date.self, from: changeTime),
               Date().timeIntervalSince(lastChange) < 3 {
                showPasteButton = true

                // Hide paste button after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    showPasteButton = false
                }
            }
        } else {
            showPasteButton = false
        }
    }

    private func pasteCode(_ code: String) {
        handlePastedCode(code)
        showPasteButton = false

        // Clear clipboard to prevent re-paste
        UIPasteboard.general.string = ""
    }

    private func handlePastedCode(_ code: String) {
        // Debounce rapid paste events
        if let lastPaste = lastPasteTime,
           Date().timeIntervalSince(lastPaste) < 0.5 {
            return
        }
        lastPasteTime = Date()

        // Extract only numbers from the pasted string
        let numbers = code.filter { $0.isNumber }

        // Animate paste
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            // Fill in the digits
            for (index, char) in numbers.prefix(numberOfDigits).enumerated() {
                digits[index] = String(char)
                animateDigit(at: index, scale: 1.1, delay: Double(index) * 0.05)
            }
        }

        // Focus the next empty field or dismiss keyboard if all filled
        if let firstEmptyIndex = digits.firstIndex(where: { $0.isEmpty }) {
            focusedIndex = firstEmptyIndex
        } else {
            focusedIndex = nil
        }

        // Announce to accessibility
        UIAccessibility.post(notification: .announcement,
                             argument: "Code pasted")
    }

    // MARK: - Animations

    private func animateDigit(at index: Int, scale: CGFloat, delay: Double = 0) {
        // Simplified animation to prevent performance issues
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            digitScales[index] = scale

            // Return to normal scale
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                digitScales[index] = 1.0
            }
        }
    }

    private func showErrorAnimation() {
        showError = true

        // Shake animation
        withAnimation(.default) {
            shakeOffset = -10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) {
                shakeOffset = 10
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.default) {
                shakeOffset = -5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.default) {
                shakeOffset = 0
            }
        }

        // Red border on all digits
        for i in 0..<numberOfDigits {
            withAnimation(.easeInOut(duration: 0.3)) {
                digitColors[i] = .error
            }
        }

        // Reset border colors after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for i in 0..<numberOfDigits {
                withAnimation(.easeInOut(duration: 0.3)) {
                    digitColors[i] = .appBorder
                }
            }
        }
    }

    private func showVerifyingAnimation() {
        isVerifying = true

        // Pulse animation on all digits
        for i in 0..<numberOfDigits {
            animateDigit(at: i, scale: 0.95, delay: Double(i) * 0.05)
        }
    }

    private func showSuccessAnimation() {
        showSuccess = true
        isVerifying = false

        // Green border and scale animation
        for i in 0..<numberOfDigits {
            withAnimation(.easeInOut(duration: 0.3).delay(Double(i) * 0.05)) {
                digitColors[i] = .success
                digitScales[i] = 1.1
            }

            // Return to normal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.05) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    digitScales[i] = 1.0
                }
            }
        }
    }
}

struct EnhancedDigitInput: View {
    @Binding var digit: String
    let isFocused: Bool
    let scale: CGFloat
    let borderColor: Color
    let index: Int
    let totalDigits: Int
    let onTextChange: (String) -> Void

    var body: some View {
        ZStack {
            // Background with animated border
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isFocused ? Color.appPrimary : borderColor,
                            lineWidth: isFocused ? 2.5 : 2
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: isFocused)
                .animation(.easeInOut(duration: 0.3), value: borderColor)

            // Hidden TextField for input
            TextField("", text: Binding(
                get: { digit },
                set: { newValue in
                    onTextChange(newValue)
                }
            ))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode) // Enable iOS autofill
            .autocorrectionDisabled(true)
            .frame(width: 48, height: 56)
            .multilineTextAlignment(.center)
            .font(.system(size: 24, weight: .semibold, design: .monospaced))
            .foregroundColor(.clear)
            .accentColor(.clear)
            .background(Color.clear)

            // Visible digit with animation
            Text(digit.isEmpty ? "•" : digit)
                .font(.system(size: digit.isEmpty ? 16 : 24,
                              weight: .semibold,
                              design: .monospaced))
                .foregroundColor(digit.isEmpty ? .appTextTertiary : .appText)
                .opacity(digit.isEmpty ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: digit)
        }
        .frame(width: 48, height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Digit \(index + 1) of \(totalDigits)")
        .accessibilityValue(digit.isEmpty ? "empty" : "entered")
        .accessibilityHint(isFocused ? "Entering digit" : "Tap to enter digit")
    }
}

// MARK: - Resend Timer View

struct ResendTimerView: View {
    @Binding var resendCooldown: Int
    let onResend: () -> Void
    @State private var animationAmount: CGFloat = 0

    var body: some View {
        VStack(spacing: 12) {
            if resendCooldown > 0 {
                // Countdown with circular progress
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.appBorder, lineWidth: 3)
                        .frame(width: 40, height: 40)

                    // Progress circle
                    Circle()
                        .trim(from: 0, to: CGFloat(60 - resendCooldown) / 60)
                        .stroke(Color.appPrimary, lineWidth: 3)
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: resendCooldown)

                    // Timer text
                    Text("\(resendCooldown)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.appText)
                }
                .accessibilityLabel("Resend available in \(resendCooldown) seconds")
                .accessibilityAddTraits(.updatesFrequently)

                Text("Resend code in \(resendCooldown)s")
                    .font(.appCaption)
                    .foregroundColor(.appTextTertiary)
            } else {
                // Resend button
                Button(action: onResend) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .rotationEffect(.degrees(animationAmount))
                        Text("Resend verification code")
                            .font(.appBodySmall)
                    }
                    .foregroundColor(.appPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.appPrimary.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.appPrimary.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .accessibilityLabel("Resend verification code")
                .accessibilityHint("Double tap to request a new code")
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        animationAmount = 360
                    }
                }
            }
        }
        .animation(.easeInOut, value: resendCooldown)
    }
}
