//
// BaseTextField.swift
// LogYourBody
//
import SwiftUI

// MARK: - TextField Configuration

struct TextFieldConfiguration {
    var style: TextFieldStyle = .default
    var hasIcon: Bool = false
    var icon: String? = nil
    var isSecure: Bool = false
    var showToggle: Bool = false
    var errorMessage: String? = nil
    var helperText: String? = nil
    var characterLimit: Int? = nil
    var cornerRadius: CGFloat = 10
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    
    enum TextFieldStyle {
        case `default`
        case outlined
        case underlined
        case custom(background: Color, border: Color?)
        
        var backgroundColor: Color {
            switch self {
            case .default: return Color(.systemGray6)
            case .outlined, .underlined: return .clear
            case .custom(let bg, _): return bg
            }
        }
        
        var borderColor: Color? {
            switch self {
            case .outlined: return .appBorder
            case .underlined: return .appBorder
            case .custom(_, let border): return border
            default: return nil
            }
        }
    }
}

// MARK: - BaseTextField

struct BaseTextField: View {
    @Binding var text: String
    let placeholder: String
    var configuration: TextFieldConfiguration = TextFieldConfiguration()
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrectionDisabled: Bool = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil
    var onChange: ((String) -> Void)? = nil
    
    @State private var isSecureTextVisible = false
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    
    private var hasError: Bool {
        configuration.errorMessage != nil
    }
    
    private var effectiveBorderColor: Color {
        if hasError {
            return .red
        } else if isFocused {
            return .appPrimary
        } else {
            return configuration.borderColor ?? .clear
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main field container
            HStack(spacing: 12) {
                // Leading icon
                if let icon = configuration.icon, configuration.hasIcon {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.appTextSecondary)
                }
                
                // Text field
                Group {
                    if configuration.isSecure && !isSecureTextVisible {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(.system(size: 16))
                .foregroundColor(.appText)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
                .submitLabel(submitLabel)
                .onSubmit {
                    onSubmit?()
                }
                .onChange(of: text) { newValue in
                    if let limit = configuration.characterLimit, newValue.count > limit {
                        text = String(newValue.prefix(limit))
                    }
                    onChange?(newValue)
                }
                .focused($isFocused)
                
                // Trailing elements
                HStack(spacing: 8) {
                    // Character count
                    if let limit = configuration.characterLimit {
                        Text("\(text.count)/\(limit)")
                            .font(.caption)
                            .foregroundColor(.appTextTertiary)
                    }
                    
                    // Secure text toggle
                    if configuration.isSecure && configuration.showToggle {
                        Button(action: {
                            isSecureTextVisible.toggle()
                        }) {
                            Image(systemName: isSecureTextVisible ? "eye.slash" : "eye")
                                .font(.system(size: 18))
                                .foregroundColor(.appTextSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Error icon
                    if hasError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(configuration.padding)
            .background(fieldBackground)
            .overlay(fieldOverlay)
            .opacity(isEnabled ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .animation(.easeInOut(duration: 0.2), value: hasError)
            
            // Helper/Error text
            if let errorMessage = configuration.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
            } else if let helperText = configuration.helperText {
                Text(helperText)
                    .font(.caption)
                    .foregroundColor(.appTextTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }
    
    @ViewBuilder
    private var fieldBackground: some View {
        switch configuration.style {
        case .underlined:
            Color.clear
        default:
            RoundedRectangle(cornerRadius: configuration.cornerRadius)
                .fill(configuration.backgroundColor)
        }
    }
    
    @ViewBuilder
    private var fieldOverlay: some View {
        switch configuration.style {
        case .underlined:
            VStack {
                Spacer()
                Rectangle()
                    .fill(effectiveBorderColor)
                    .frame(height: isFocused ? 2 : 1)
            }
        default:
            if effectiveBorderColor != .clear {
                RoundedRectangle(cornerRadius: configuration.cornerRadius)
                    .stroke(effectiveBorderColor, lineWidth: isFocused ? 2 : 1)
            }
        }
    }
}

// MARK: - Convenience Extensions

extension TextFieldConfiguration {
    static var email: TextFieldConfiguration {
        TextFieldConfiguration(
            hasIcon: true,
            icon: "envelope"
        )
    }
    
    static var password: TextFieldConfiguration {
        TextFieldConfiguration(
            hasIcon: true,
            icon: "lock",
            isSecure: true,
            showToggle: true
        )
    }
    
    static var search: TextFieldConfiguration {
        TextFieldConfiguration(
            hasIcon: true,
            icon: "magnifyingglass",
            cornerRadius: 20
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            // Default style
            Group {
                Text("Default Style").font(.headline)
                BaseTextField(
                    text: .constant(""),
                    placeholder: "Enter your name"
                )
                
                BaseTextField(
                    text: .constant("john@example.com"),
                    placeholder: "Email",
                    configuration: .email,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    autocapitalization: .never
                )
            }
            
            Divider()
            
            // Outlined style
            Group {
                Text("Outlined Style").font(.headline)
                BaseTextField(
                    text: .constant(""),
                    placeholder: "Username",
                    configuration: TextFieldConfiguration(style: .outlined)
                )
            }
            
            Divider()
            
            // Underlined style
            Group {
                Text("Underlined Style").font(.headline)
                BaseTextField(
                    text: .constant(""),
                    placeholder: "Full Name",
                    configuration: TextFieldConfiguration(style: .underlined)
                )
            }
            
            Divider()
            
            // Password field
            Group {
                Text("Password Field").font(.headline)
                BaseTextField(
                    text: .constant(""),
                    placeholder: "Password",
                    configuration: .password,
                    textContentType: .password
                )
            }
            
            Divider()
            
            // With character limit
            Group {
                Text("Character Limit").font(.headline)
                BaseTextField(
                    text: .constant("Hello"),
                    placeholder: "Bio",
                    configuration: TextFieldConfiguration(
                        characterLimit: 150,
                        helperText: "Tell us about yourself"
                    )
                )
            }
            
            Divider()
            
            // Error state
            Group {
                Text("Error State").font(.headline)
                BaseTextField(
                    text: .constant("invalid@"),
                    placeholder: "Email",
                    configuration: TextFieldConfiguration(
                        hasIcon: true,
                        icon: "envelope",
                        errorMessage: "Please enter a valid email address"
                    )
                )
            }
            
            Divider()
            
            // Search field
            Group {
                Text("Search Field").font(.headline)
                BaseTextField(
                    text: .constant(""),
                    placeholder: "Search...",
                    configuration: .search
                )
            }
            
            Divider()
            
            // Disabled state
            Group {
                Text("Disabled State").font(.headline)
                BaseTextField(
                    text: .constant("Disabled"),
                    placeholder: "Cannot edit"
                )
                .disabled(true)
            }
        }
        .padding()
    }
    .background(Color.appBackground)
}