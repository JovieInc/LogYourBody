//
// DashboardViewSimple.swift
// LogYourBody
//
import SwiftUI

struct DashboardViewSimple: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Dashboard")
                    .font(.largeTitle)
                    .foregroundColor(.white)

                if let user = authManager.currentUser {
                    Text("Welcome, \(user.profile?.fullName ?? "User")!")
                        .foregroundColor(.white)
                } else {
                    Text("Welcome!")
                        .foregroundColor(.white)
                }

                Text("Your dashboard is loading...")
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            }
        }
    }
}
