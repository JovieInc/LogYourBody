//
// StandardTextField.swift
// LogYourBody
//
import SwiftUI

// MARK: - Text Field Style Enum

enum TextFieldStyle {
    case standard
    case filled
    case outlined
}

// MARK: - Standard Text Field

struct StandardTextField: View {
    @FocusState private var isFocused: Bool

    @Binding var text: String
    let placeholder: String
    let label: String?
    let icon: String?
    let style: TextFieldStyle
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let errorMessage: String?
    let helperText: String?
    let characterLimit: Int?
    let onEditingChanged: ((Bool) -> Void)?
    let onCommit: (() -> Void)?

    @State private var showPassword = false

    private var isSecureField: Bool {
        textContentType == .password || textContentType == .newPassword
    }

    init(
        text: Binding<String>,
        placeholder: String = "",
        label: String? = nil,
        icon: String? = nil,
        style: TextFieldStyle = .standard,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        errorMessage: String? = nil,
        helperText: String? = nil,
        characterLimit: Int? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.label = label
        self.icon = icon
        self.style = style
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.errorMessage = errorMessage
        self.helperText = helperText
        self.characterLimit = characterLimit
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            if let label = label {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // Text Field Container
            HStack(spacing: 8) {
                // Leading icon
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                        .transition(.opacity)
                }

                // Text Field
                Group {
                    if isSecureField && !showPassword {
                        SecureField(placeholder, text: $text) {
                            onCommit?()
                        }
                    } else {
                        TextField(placeholder, text: $text) { editing in
                            onEditingChanged?(editing)
                        } onCommit: {
                            onCommit?()
                        }
                    }
                }
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .autocapitalization(textContentType == .emailAddress ? .none : .sentences)
                .disableAutocorrection(textContentType == .emailAddress || isSecureField)
                .font(.body)
                .foregroundColor(.primary)
                .focused($isFocused)

                // Trailing elements
                HStack(spacing: 4) {
                    // Character count
                    if let limit = characterLimit {
                        Text("\(text.count)/\(limit)")
                            .font(.caption2)
                            .foregroundColor(
                                text.count > limit ? .red : Color.secondary.opacity(0.6)
                            )
                    }

                    // Password toggle
                    if isSecureField {
                        Button(
                            action: { showPassword.toggle() },
                            label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                        )
                    }

                    // Clear button
                    if !text.isEmpty && isFocused {
                        Button(
                            action: { text = "" },
                            label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.secondary.opacity(0.6))
                            }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundView)
            .cornerRadius(6)
            .overlay(overlayView)
            .animation(.easeOut(duration: 0.2), value: isFocused)
            .animation(.easeOut(duration: 0.2), value: errorMessage != nil)

            // Helper/Error text
            if let error = errorMessage {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(.caption)
                }
                .foregroundColor(.red)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let helper = helperText {
                Text(helper)
                    .font(.caption)
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
    }

    // MARK: - Computed Properties

    @ViewBuilder private var backgroundView: some View {
        switch style {
        case .standard:
            Color.appCard
        case .filled:
            Color.appCard.opacity(0.8)
        case .outlined:
            Color.clear
        }
    }

    @ViewBuilder private var overlayView: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(borderColor, lineWidth: borderWidth)
    }

    private var borderColor: Color {
        if errorMessage != nil {
            return .red
        } else if isFocused {
            return Color.appPrimary
        } else {
            switch style {
            case .outlined:
                return Color.appBorder
            default:
                return Color.clear
            }
        }
    }

    private var borderWidth: CGFloat {
        if isFocused || errorMessage != nil {
            return 2
        } else {
            return style == .outlined ? 1 : 0
        }
    }

    private var iconColor: Color {
        if errorMessage != nil {
            return .red
        } else if isFocused {
            return .appPrimary
        } else {
            return .secondary
        }
    }
}

// MARK: - Search Field

struct SearchField: View {
    @FocusState private var isFocused: Bool

    @Binding var text: String
    let placeholder: String
    let onSearch: (() -> Void)?

    init(
        text: Binding<String>,
        placeholder: String = "Search",
        onSearch: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSearch = onSearch
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text) {
                onSearch?()
            }
            .font(.body)
            .foregroundColor(.primary)
            .focused($isFocused)

            if !text.isEmpty {
                Button(
                    action: { text = "" },
                    label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.secondary.opacity(0.6))
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appCard)
        .cornerRadius(999)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(isFocused ? Color.appPrimary : Color.clear, lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Text Area

struct TextArea: View {
    @FocusState private var isFocused: Bool

    @Binding var text: String
    let placeholder: String
    let label: String?
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let characterLimit: Int?
    let errorMessage: String?

    init(
        text: Binding<String>,
        placeholder: String = "",
        label: String? = nil,
        minHeight: CGFloat = 100,
        maxHeight: CGFloat = 300,
        characterLimit: Int? = nil,
        errorMessage: String? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.label = label
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.characterLimit = characterLimit
        self.errorMessage = errorMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            if let label = label {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // Text Editor
            ZStack(alignment: .topLeading) {
                // Placeholder
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }

                // Text Editor
                TextEditor(text: $text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isFocused)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
            }
            .padding(8)
            .background(Color.appCard)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: borderWidth)
            )

            // Footer
            HStack {
                // Error message
                if let error = errorMessage {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                        Text(error)
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                // Character count
                if let limit = characterLimit {
                    Text("\(text.count)/\(limit)")
                        .font(.caption2)
                        .foregroundColor(
                            text.count > limit ? .red : Color.secondary.opacity(0.6)
                        )
                }
            }
        }
    }

    private var borderColor: Color {
        if errorMessage != nil {
            return .red
        } else if isFocused {
            return Color.appPrimary
        } else {
            return Color.appBorder
        }
    }

    private var borderWidth: CGFloat {
        isFocused || errorMessage != nil ? 2 : 1
    }
}

// MARK: - Preview

struct StandardTextField_Previews: PreviewProvider {
    static var previews: some View {
        ThemePreview {
            ScrollView {
                VStack(spacing: 24) {
                    // Standard text fields
                    StandardTextField(
                        text: .constant(""),
                        placeholder: "Enter your name",
                        label: "Name",
                        icon: "person"
                    )

                    StandardTextField(
                        text: .constant("john@example.com"),
                        placeholder: "Enter your email",
                        label: "Email",
                        icon: "envelope",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )

                    // Password field
                    StandardTextField(
                        text: .constant("password123"),
                        placeholder: "Enter your password",
                        label: "Password",
                        icon: "lock",
                        textContentType: .password
                    )

                    // With error
                    StandardTextField(
                        text: .constant("invalid"),
                        placeholder: "Enter value",
                        label: "Field with Error",
                        errorMessage: "This field is required"
                    )

                    // With helper text
                    StandardTextField(
                        text: .constant(""),
                        placeholder: "Enter username",
                        label: "Username",
                        helperText: "Choose a unique username"
                    )

                    // With character limit
                    StandardTextField(
                        text: .constant("Hello"),
                        placeholder: "Bio",
                        label: "Short Bio",
                        characterLimit: 50
                    )

                    // Search field
                    SearchField(text: .constant(""))

                    // Text area
                    TextArea(
                        text: .constant(""),
                        placeholder: "Tell us about yourself...",
                        label: "About",
                        characterLimit: 500
                    )
                }
                .padding()
            }
            .background(Color.black)
        }
    }
}
