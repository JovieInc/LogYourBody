//
// SettingsRow.swift
// LogYourBody
//
import SwiftUI

// MARK: - Settings Row Type

enum SettingsRowType {
    case navigation
    case toggle(isOn: Binding<Bool>)
    case value(text: String)
    case action
    case picker(selection: Binding<String>, options: [String])
    case stepper(value: Binding<Int>, range: ClosedRange<Int>)
}

// MARK: - Settings Row

struct DesignSettingsRow: View {
    let icon: String?
    let iconColor: Color?
    let title: String
    let subtitle: String?
    let type: SettingsRowType
    let action: (() -> Void)?
    
    @State private var isPressed = false
    
    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        type: SettingsRowType = .navigation,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.action = action
    }
    
    var body: some View {
        Button(
            action: {
                if case .navigation = type {
                    // // HapticManager.shared.selection()
                    action?()
                } else if case .action = type {
                    // // HapticManager.shared.impact(style: .light)
                    action?()
                }
            },
            label: {
                HStack(spacing: 12) {
                    // Icon
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor ?? .appPrimary)
                        .frame(width: 28, height: 28)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Trailing content
                trailingContent
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Color.appBackground
                        .opacity(isPressed ? 0.5 : 0)
                )
                .contentShape(Rectangle())
            }
        )
        .buttonStyle(PlainButtonStyle())
        .disabled(!isInteractive)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            if isInteractive {
                withAnimation(.easeOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }
        }, perform: {})
    }
    
    @ViewBuilder private var trailingContent: some View {
        switch type {
        case .navigation:
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.secondary.opacity(0.6))
                
        case .toggle(let isOn):
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.appPrimary)
                
        case .value(let text):
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
                
        case .action:
            EmptyView()
                
        case .picker(let selection, let options):
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(
                        action: {
                            selection.wrappedValue = option
                        },
                        label: {
                        HStack {
                            Text(option)
                            if selection.wrappedValue == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    })
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.wrappedValue)
                        .font(.body)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
            }
            
        case .stepper(let value, let range):
            Stepper(
                value: value,
                in: range
            ) {
                Text("\(value.wrappedValue)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .labelsHidden()
        }
    }
    
    private var isInteractive: Bool {
        switch type {
        case .navigation, .action:
            return true
        default:
            return false
        }
    }
}

// MARK: - Settings Section

struct DesignSettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: () -> Content
    
    init(
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if let title = title {
                Text(title.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            
            // Content with separators
            VStack(spacing: 0) {
                content()
            }
            .background(Color.appCard)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            
            // Footer
            if let footer = footer {
                Text(footer)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - List Row

struct ListRow: View {
    let title: String
    let subtitle: String?
    let leading: AnyView?
    let trailing: AnyView?
    let action: (() -> Void)?
    
    @State private var isPressed = false
    
    init(
        title: String,
        subtitle: String? = nil,
        leading: AnyView? = nil,
        trailing: AnyView? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
        self.action = action
    }
    
    var body: some View {
        Button(
            action: {
                // // HapticManager.shared.selection()
                action?()
            },
            label: {
                HStack(spacing: 12) {
                    // Leading content
                if let leading = leading {
                    leading
                }
                
                // Main content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Trailing content
                if let trailing = trailing {
                    trailing
                } else if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Color.appBackground
                        .opacity(isPressed ? 0.5 : 0)
                )
                .contentShape(Rectangle())
            }
        )
        .buttonStyle(PlainButtonStyle())
        .disabled(action == nil)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            if action != nil {
                withAnimation(.easeOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }
        }, perform: {})
    }
}

// MARK: - Destructive Row

struct DestructiveRow: View {
    let title: String
    let icon: String?
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(
            action: {
                // // HapticManager.shared.impact(style: .medium)
                action()
            },
            label: {
                HStack(spacing: 12) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                    }
                    
                    Text(title)
                        .font(.body)
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    .red
                        .opacity(isPressed ? 0.1 : 0)
                )
                .contentShape(Rectangle())
            }
        )
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Preview

struct SettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        ThemePreview {
            ScrollView {
                VStack(spacing: 0) {
                    // Settings sections
                    DesignSettingsSection(title: "Account") {
                        DesignSettingsRow(
                            icon: "person.circle",
                            title: "Profile",
                            subtitle: "John Doe",
                            type: .navigation
                        ) { }
                        
                        Divider()
                            .background(Color(white: 0.15))
                            .padding(.leading, 60)
                        
                        DesignSettingsRow(
                            icon: "envelope",
                            title: "Email",
                            type: .value(text: "john@example.com")
                        )
                    }
                    
                    DesignSettingsSection(title: "Preferences") {
                        DesignSettingsRow(
                            icon: "moon",
                            title: "Dark Mode",
                            type: .toggle(isOn: .constant(true))
                        )
                        
                        Divider()
                            .background(Color(white: 0.15))
                            .padding(.leading, 60)
                        
                        DesignSettingsRow(
                            icon: "textformat",
                            title: "Font Size",
                            type: .picker(
                                selection: .constant("Medium"),
                                options: ["Small", "Medium", "Large"]
                            )
                        )
                        
                        Divider()
                            .background(Color(white: 0.15))
                            .padding(.leading, 60)
                        
                        DesignSettingsRow(
                            icon: "bell",
                            title: "Notifications",
                            subtitle: "Manage notification preferences",
                            type: .navigation
                        ) { }
                    }
                    
                    DesignSettingsSection(
                        title: "Data",
                        footer: "Your data will be permanently deleted"
                    ) {
                        DestructiveRow(
                            title: "Delete Account",
                            icon: "trash"
                        ) { }
                    }
                    
                    // List rows
                    DesignSettingsSection(title: "Recent Activity") {
                        ListRow(
                            title: "Workout Session",
                            subtitle: "45 minutes • 320 calories",
                            leading: AnyView(
                                Image(systemName: "figure.run")
                                    .font(.system(size: 24))
                                    .foregroundColor(.orange)
                            ),
                            trailing: AnyView(
                                Text("2h ago")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            )
                        ) { }
                        
                        Divider()
                            .background(Color(white: 0.15))
                        
                        ListRow(
                            title: "Weight Entry",
                            subtitle: "72.5 kg",
                            leading: AnyView(
                                Image(systemName: "scalemass")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                            ),
                            trailing: AnyView(
                                Text("Yesterday")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            )
                        ) { }
                    }
                }
            }
            .background(Color.black)
        }
    }
}
