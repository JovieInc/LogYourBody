//
// DSAuthLink.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSAuthLink Atom

struct DSAuthLink: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.appTextSecondary)
                .underline()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Navigation Link Variant

struct DSAuthNavigationLink<Destination: View>: View {
    let title: String
    let destination: Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.appTextSecondary)
                .underline()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        DSAuthLink(title: "Forgot password?") {
            // Action
        }
        
        DSAuthNavigationLink(
            title: "Create an account",
            destination: Text("Sign Up View")
        )
        
        HStack(spacing: 4) {
            Text("Already have an account?")
                .font(.system(size: 15))
                .foregroundColor(.appTextSecondary)
            
            DSAuthLink(title: "Sign in") {
                // Action
            }
        }
    }
    .padding()
    .background(Color.appBackground)
}
