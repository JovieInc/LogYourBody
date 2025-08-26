//
// AuthConsentCheckbox.swift
// LogYourBody
//
import SwiftUI

// MARK: - AuthConsentCheckbox Molecule

struct AuthConsentCheckbox: View {
    @Binding var isChecked: Bool
    let text: String
    let linkText: String
    let url: URL
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: { isChecked.toggle() }, label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isChecked ? .appPrimary : .appBorder)
            })
            .buttonStyle(PlainButtonStyle())
            
            // Text with link
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("I agree to the")
                        .font(.system(size: 14))
                        .foregroundColor(.appTextSecondary)
                    
                    Link(linkText, destination: url)
                        .font(.system(size: 14))
                        .foregroundColor(.appPrimary)
                        .underline()
                }
                .multilineTextAlignment(.leading)
                
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.appTextTertiary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AuthConsentCheckbox(
            isChecked: .constant(true),
            text: "LogYourBody's terms of service",
            linkText: "Terms of Service",
            url: URL(string: "https://logyourbody.com/terms")!
        )
        
        AuthConsentCheckbox(
            isChecked: .constant(false),
            text: "How we handle your data",
            linkText: "Privacy Policy",
            url: URL(string: "https://logyourbody.com/privacy")!
        )
        
        AuthConsentCheckbox(
            isChecked: .constant(false),
            text: "Important health information",
            linkText: "Health Disclaimer",
            url: URL(string: "https://logyourbody.com/health-disclaimer")!
        )
    }
    .padding()
    .background(Color.appBackground)
}
