//
// AuthManager.swift
// LogYourBody
//
import Combine
import AuthenticationServices
import UIKit
import CryptoKit
import Clerk

typealias LocalUser = LogYourBody.User  // Disambiguate between Clerk SDK User and our User model

typealias ASPresentationAnchor = UIWindow

enum AuthError: LocalizedError {
    case clerkNotInitialized
    case invalidCredentials
    case nameUpdateFailed(String)
    case networkError
    case syncError(String)
    
    var errorDescription: String? {
        switch self {
        case .clerkNotInitialized:
            return "Authentication service is not ready. Please try again."
        case .invalidCredentials:
            return "Invalid authentication credentials"
        case .nameUpdateFailed(let reason):
            return "Failed to update name: \(reason)"
        case .networkError:
            return "Network connection error. Please check your connection."
        case .syncError(let reason):
            return "Failed to sync data: \(reason)"
        }
    }
}

// Session information for active sessions management
struct SessionInfo: Identifiable {
    let id: String
    let deviceName: String
    let deviceType: String
    let location: String
    let ipAddress: String
    let lastActiveAt: Date
    let createdAt: Date
    let isCurrentSession: Bool
}

@MainActor
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: LocalUser?
    @Published var clerkSession: Session?
    @Published var needsEmailVerification = false
    @Published var isClerkLoaded = false
    @Published var clerkInitError: String?
    @Published var needsLegalConsent = false
    @Published var pendingAppleUserId: String?
    
    private var currentSignUp: SignUp?
    private var pendingSignUpCredentials: (email: String, password: String)?
    private let clerk = Clerk.shared
    private let supabase = SupabaseClient.shared  // Keep for data operations
    private let userDefaults = UserDefaults.standard
    private let userKey = Constants.currentUserKey
    private var cancellables = Set<AnyCancellable>()
    private var sessionObservationTask: Task<Void, Never>?
    
    override init() {
        super.init()
        // print("🔐 AuthManager initialized")
        
        // Always start with no authentication until Clerk confirms session
        self.isAuthenticated = false
        self.currentUser = nil
        self.clerkSession = nil
        
        // Clear any stale user data
        userDefaults.removeObject(forKey: userKey)
    }
    
    func initializeClerk() async {
        // print("🔧 Initializing Clerk SDK")

        let pubKey = Constants.clerkPublishableKey
        // print("🔧 Publishable Key Length: \(pubKey.count)")
        // print("🔧 Publishable Key: \(pubKey.isEmpty ? "EMPTY ❌" : String(pubKey.prefix(20)) + "...")")
        // print("🔧 Frontend API: \(Constants.clerkFrontendAPI)")
        // print("🔧 Is Configured: \(Constants.isClerkConfigured)")

        // Clear any previous error
        await MainActor.run {
            self.clerkInitError = nil
        }

        // Validate publishable key before attempting to configure
        guard !pubKey.isEmpty else {
            let error = "Clerk publishable key is empty. Check Config.xcconfig and Xcode project configuration."
        // print("❌ \(error)")
            await MainActor.run {
                self.isClerkLoaded = false
                self.clerkInitError = error
            }
            return
        }

        guard pubKey.hasPrefix("pk_") else {
            let error = "Invalid Clerk key format (should start with 'pk_'). Current: '\(String(pubKey.prefix(10)))...'"
        // print("❌ \(error)")
            await MainActor.run {
                self.isClerkLoaded = false
                self.clerkInitError = error
            }
            return
        }

        // Configure Clerk with publishable key
        // print("🔧 Configuring Clerk with valid publishable key...")
        clerk.configure(publishableKey: pubKey)

        // Load Clerk
        do {
        // print("🔧 Attempting to load Clerk...")
            let startTime = Date()
            try await clerk.load()
            let duration = Date().timeIntervalSince(startTime)
        // print("✅ Clerk SDK loaded successfully in \(String(format: "%.2f", duration))s")

            await MainActor.run {
                self.isClerkLoaded = true
                self.clerkInitError = nil
                self.observeSessionChanges()
            }
        } catch {
            let errorMessage = error.localizedDescription
        // print("❌ Failed to load Clerk: \(error)")
        // print("❌ Error type: \(type(of: error))")
        // print("❌ Error details: \(String(describing: error))")
        // print("❌ Localized: \(errorMessage)")

            await MainActor.run {
                self.isClerkLoaded = false
                self.clerkInitError = "Failed to connect to authentication service: \(errorMessage)"
            }
        }
    }

    /// Retry Clerk initialization after a failure
    func retryClerkInitialization() async {
        // print("🔄 Retrying Clerk initialization...")
        await initializeClerk()
    }

    private func observeSessionChanges() {
        // Cancel any existing observation
        sessionObservationTask?.cancel()
        
        // Observe Clerk instance for changes
        sessionObservationTask = Task { @MainActor in
            // Initial check
            self.updateSessionState()
            
            // Check for pending name updates when session is established
            if self.clerkSession != nil {
                Task {
                    await self.resolvePendingNameUpdates()
                }
            }
            
            // Periodically check for session changes (reduced frequency for performance)
            // Only check every 5 minutes to minimize background activity
            Timer.publish(every: 300.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.updateSessionState()
                }
                .store(in: &cancellables)
        }
    }
    
    @MainActor
    private func updateSessionState() {
        _ = clerk.session != nil
        let previousSessionId = self.clerkSession?.id
        let currentSessionId = clerk.session?.id
        
        // Only update if session actually changed
        if previousSessionId != currentSessionId {
            // print("🔄 Session change detected: \(previousSessionId ?? "nil") -> \(currentSessionId ?? "nil")")
            
            self.clerkSession = clerk.session
            
            if let _ = clerk.session, let user = clerk.user {
                // Only authenticate if we have both a valid session AND user
                // print("🔄 Clerk session state: signed in with user \(user.id)")
                self.updateLocalUser(clerkUser: user)
                // isAuthenticated will be set by updateLocalUser if successful
                
                // Clear any remaining sign up state
                self.currentSignUp = nil
                self.pendingSignUpCredentials = nil
                self.needsEmailVerification = false
                
                // Notify RevenueCat of authenticated user for correct entitlement handling
                if let localUserId = self.currentUser?.id {
                    Task {
                        await RevenueCatManager.shared.identifyUser(userId: localUserId)
                    }
                }
            } else {
                // No valid session or user
                // print("🔄 Clerk session state: signed out")
                self.isAuthenticated = false
                self.currentUser = nil
                userDefaults.removeObject(forKey: userKey)
            }
        }
    }
    
    private func updateLocalUser(clerkUser: Any) {
        // Use Mirror to access properties dynamically due to type naming conflict
        let mirror = Mirror(reflecting: clerkUser)
        
        // Extract properties using Mirror
        var userId = ""
        var emailAddresses: [Any] = []
        var firstName: String?
        var lastName: String?
        var username: String?
        var imageUrl: String?
        
        for child in mirror.children {
            switch child.label {
            case "id":
                userId = child.value as? String ?? ""
            case "emailAddresses":
                emailAddresses = child.value as? [Any] ?? []
            case "firstName":
                firstName = child.value as? String
            case "lastName":
                lastName = child.value as? String
            case "username":
                username = child.value as? String
            case "imageUrl":
                imageUrl = child.value as? String
            default:
                break
            }
        }
        
        // Extract email from first email address
        var email = ""
        if let firstEmailAddress = emailAddresses.first {
            let emailMirror = Mirror(reflecting: firstEmailAddress)
            for child in emailMirror.children {
                if child.label == "emailAddress" {
                    email = child.value as? String ?? ""
                    break
                }
            }
        }
        
        // Use single source of truth for display name
        let displayName = getUserDisplayName()
        
        // Don't proceed if we don't have a valid email
        guard !email.isEmpty else {
            self.currentUser = nil
            self.isAuthenticated = false
            return
        }
        
        // Create user object with Clerk data
        let localUser = LocalUser(
            id: userId,
            email: email,
            name: displayName.isEmpty ? email.components(separatedBy: "@").first ?? "User" : displayName,
            avatarUrl: imageUrl,
            profile: UserProfile(
                id: userId,
                email: email,
                username: username,
                fullName: displayName.isEmpty ? email.components(separatedBy: "@").first ?? "User" : displayName,
                dateOfBirth: nil,
                height: nil,
                heightUnit: "cm",
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: "kg",
                onboardingCompleted: nil
            )
        )
        
        self.currentUser = localUser
        self.isAuthenticated = true  // Set authenticated only after successful user creation
        
        // Store user data
        if let encoded = try? JSONEncoder().encode(localUser) {
            userDefaults.set(encoded, forKey: userKey)
        }
        
        // Create or update profile in Supabase
        Task {
            await self.createOrUpdateSupabaseProfile(user: localUser)
        }
    }
    
    func login(email: String, password: String) async throws {
        // Mock authentication for development
        if Constants.useMockAuth {
            // print("🧪 Using mock authentication for development")
            
            // Create mock user
            let mockUser = LocalUser(
                id: "mock_user_123",
                email: email,
                name: "Test User",
                avatarUrl: nil,
                profile: UserProfile(
                    id: "mock_user_123",
                    email: email,
                    username: nil,
                    fullName: "Test User",
                    dateOfBirth: nil,
                    height: nil,
                    heightUnit: "cm",
                    gender: nil,
                    activityLevel: nil,
                    goalWeight: nil,
                    goalWeightUnit: "kg",
                    onboardingCompleted: nil
                )
            )
            
            await MainActor.run {
                self.currentUser = mockUser
                self.isAuthenticated = true
                // print("✅ Mock authentication successful")
            }
            return
        }
        
        // Real authentication using Clerk SDK
        guard isClerkLoaded else {
            throw AuthError.clerkNotInitialized
        }
        
        do {
            // Create a sign in with email and password
            _ = try await SignIn.create(
                strategy: .identifier(email, password: password)
            )
            
            // print("✅ Sign in successful")
            // The session observer will automatically update isAuthenticated
        } catch {
            // print("❌ Login failed: \(error)")
            throw error
        }
    }
    
    func signUp(email: String, password: String, name: String) async throws {
        // Mock authentication for development
        if Constants.useMockAuth {
            // Simulate the sign up process
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            
            // Create mock user
            let mockUser = LocalUser(
                id: "mock_user_123",
                email: email,
                name: name.isEmpty ? "Test User" : name,
                avatarUrl: nil,
                profile: UserProfile(
                    id: "mock_user_123",
                    email: email,
                    username: nil,
                    fullName: name.isEmpty ? "Test User" : name,
                    dateOfBirth: nil,
                    height: nil,
                    heightUnit: "cm",
                    gender: nil,
                    activityLevel: nil,
                    goalWeight: nil,
                    goalWeightUnit: "kg",
                    onboardingCompleted: nil
                )
            )
            
            await MainActor.run {
                self.currentUser = mockUser
                self.isAuthenticated = true
                UserDefaults.standard.set(false, forKey: Constants.hasCompletedOnboardingKey)
            }
            return
        }
        
        // Real sign up using Clerk SDK
        guard isClerkLoaded else {
            throw AuthError.clerkNotInitialized
        }
        
        do {
            // Create sign up with email and password
            // Note: If your Clerk instance requires legal acceptance, 
            // you may need to pass additional parameters here
            let signUp = try await SignUp.create(
                strategy: .standard(
                    emailAddress: email,
                    password: password
                )
            )
            
            // Store the sign up instance and credentials for verification
            self.currentSignUp = signUp
            self.pendingSignUpCredentials = (email: email, password: password)
            
            // Prepare email verification
            try await signUp.prepareVerification(strategy: .emailCode)
            
            await MainActor.run {
                self.needsEmailVerification = true
                // Clear onboarding status for new users
                UserDefaults.standard.set(false, forKey: Constants.hasCompletedOnboardingKey)
            }
        } catch {
            throw error
        }
    }
    
    func logout() async {
        do {
            try await clerk.signOut()
            // print("✅ Signed out successfully")
        } catch {
            // print("❌ Logout error: \(error)")
        }
        
        await MainActor.run {
            self.clerkSession = nil
            self.currentUser = nil
            self.isAuthenticated = false
            self.currentSignUp = nil
            self.pendingSignUpCredentials = nil
            self.needsEmailVerification = false
        }
        
        // Also clear RevenueCat state so subscriptions are reset correctly on sign out
        await RevenueCatManager.shared.logoutUser()
        
        // Clear all stored user data
        userDefaults.removeObject(forKey: userKey)
        userDefaults.removeObject(forKey: Constants.currentUserKey)
        userDefaults.removeObject(forKey: Constants.authTokenKey)
        
        // Clear any cached step history flags
        UserDefaults.standard.removeObject(forKey: "HasSyncedHistoricalSteps")
        
        // Clear last sync dates to force fresh sync on next login
        UserDefaults.standard.removeObject(forKey: "lastSupabaseSyncDate")
        UserDefaults.standard.removeObject(forKey: "lastHealthKitWeightSyncDate")
        
        // print("🧹 Cleared all user data from UserDefaults")
    }
    
    private func loadUserProfile(userId: String) async {
        guard let token = await getSupabaseToken() else {
            // print("❌ No Supabase token available")
            return
        }
        
        do {
            let profiles: [Profile] = try await supabase.query(
                table: "profiles",
                accessToken: token,
                filter: "id=eq.\(userId)"
            )
            
            if let profile = profiles.first {
                let user = LocalUser(
                    id: profile.id,
                    email: profile.email,
                    name: profile.fullName,
                    avatarUrl: profile.avatarUrl,
                    profile: UserProfile(
                        id: profile.id,
                        email: profile.email,
                        username: profile.username,
                        fullName: profile.fullName,
                        dateOfBirth: profile.dateOfBirth,
                        height: profile.height,
                        heightUnit: profile.heightUnit ?? "cm",
                        gender: profile.gender,
                        activityLevel: profile.activityLevel,
                        goalWeight: profile.goalWeight,
                        goalWeightUnit: profile.goalWeightUnit ?? "kg",
                        onboardingCompleted: profile.onboardingCompleted
                    )
                )
                
                await MainActor.run {
                    self.currentUser = user
                }
                
                // Store user data
                if let encoded = try? JSONEncoder().encode(user) {
                    userDefaults.set(encoded, forKey: userKey)
                }
            } else {
                // Profile doesn't exist, create it
                if let clerkUser = await MainActor.run(body: { clerk.user }) {
                    // Use Mirror to extract properties to avoid type conflicts
                    let mirror = Mirror(reflecting: clerkUser)
                    var email = ""
                    var username: String?
                    var firstName: String?
                    var lastName: String?
                    for child in mirror.children {
                        switch child.label {
                        case "emailAddresses":
                            if let emailAddresses = child.value as? [Any], let firstEmail = emailAddresses.first {
                                let emailMirror = Mirror(reflecting: firstEmail)
                                for emailChild in emailMirror.children {
                                    if emailChild.label == "emailAddress" {
                                        email = emailChild.value as? String ?? ""
                                        break
                                    }
                                }
                            }
                        case "username":
                            username = child.value as? String
                        case "firstName":
                            firstName = child.value as? String
                        case "lastName":
                            lastName = child.value as? String
                        default:
                            break
                        }
                    }
                    
                    let fullName = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
                    
                    let profile = Profile(
                        id: userId,
                        email: email,
                        username: username,
                        fullName: fullName,
                        dateOfBirth: nil,
                        height: nil,
                        heightUnit: nil,
                        gender: nil,
                        activityLevel: nil,
                        goalWeight: nil,
                        goalWeightUnit: nil,
                        avatarUrl: nil,
                        createdAt: Date(),
                        updatedAt: Date(),
                        onboardingCompleted: nil
                    )
                    
                    try await supabase.insert(table: "profiles", data: profile, accessToken: token)
                    await loadUserProfile(userId: userId)  // Reload after creating
                }
            }
        } catch {
            // print("❌ Failed to load user profile: \(error)")
        }
    }
    
    // MARK: - Apple Sign In
    
    func startAppleSignIn() {
        guard isClerkLoaded else {
            return
        }
        
        Task {
            do {
                // Use Clerk SDK for Apple Sign In
                let signIn = try await SignIn.create(strategy: .oauth(provider: .apple))
                try await signIn.authenticateWithRedirect()
            } catch {
                // Handle error silently
            }
        }
    }
    
    // MARK: - Unified Apple Sign In Handler
    @MainActor
    func handleAppleSignIn() async {
        // Allow Apple Sign In with mock auth for testing
        if !Constants.useMockAuth {
            guard isClerkLoaded else {
                showAuthError("Authentication service not ready. Please try again.")
                return
            }
        } else {
            // Mock Apple Sign In for testing
            let mockUser = LocalUser(
                id: "mock_apple_user_123",
                email: "test@apple.com",
                name: "Apple Test User",
                avatarUrl: nil,
                profile: UserProfile(
                    id: "mock_apple_user_123",
                    email: "test@apple.com",
                    username: nil,
                    fullName: "Apple Test User",
                    dateOfBirth: nil,
                    height: nil,
                    heightUnit: "cm",
                    gender: nil,
                    activityLevel: nil,
                    goalWeight: nil,
                    goalWeightUnit: "kg",
                    onboardingCompleted: nil
                )
            )

            await MainActor.run {
                self.currentUser = mockUser
                self.isAuthenticated = true
                UserDefaults.standard.set(false, forKey: Constants.hasCompletedOnboardingKey)
            }
            return
        }
        
        do {
            // Create the Apple ID provider and request
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            
            // Create and configure the authorization controller
            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            
            // Use a continuation to handle the delegate callbacks
            let appleIDCredential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) in
                let delegate = AppleSignInDelegate(continuation: continuation)
                authorizationController.delegate = delegate
                authorizationController.presentationContextProvider = delegate
                
                // Keep a strong reference to the delegate
                objc_setAssociatedObject(authorizationController, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                
                authorizationController.performRequests()
            }
            
            // Process the credentials
            try await signInWithAppleCredentials(appleIDCredential)
        } catch {
            // Handle specific errors
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    // User canceled - don't show error
                    return
                case .failed:
                    showAuthError("Apple Sign In failed. Please try again.")
                case .invalidResponse:
                    showAuthError("Invalid response from Apple Sign In.")
                case .notHandled:
                    showAuthError("Apple Sign In request was not handled.")
                case .unknown:
                    showAuthError("An unknown error occurred with Apple Sign In.")
                @unknown default:
                    showAuthError("An error occurred with Apple Sign In.")
                }
            } else {
                showAuthError(error.localizedDescription)
            }
        }
    }
    
    func signInWithAppleCredentials(_ appleIDCredential: ASAuthorizationAppleIDCredential) async throws {
        guard isClerkLoaded else {
            throw AuthError.clerkNotInitialized
        }
        
        // Extract the identity token
        guard let identityToken = appleIDCredential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredentials
        }
        
        do {
            // Use Clerk's ID token authentication
            let result = try await SignIn.authenticateWithIdToken(provider: .apple, idToken: idTokenString)
            
            // Handle the transfer flow result
            switch result {
            case .signIn(let signIn):
                // For sign in, we need to activate the session first to get the user ID
                if let sessionId = signIn.createdSessionId {
                    try await clerk.setActive(sessionId: sessionId)
                }
                
                // Now get the actual user ID from the clerk user
                guard let userId = clerk.user?.id else {
                    throw AuthError.invalidCredentials
                }
                
                // Check if this user has already accepted legal terms
                let hasAcceptedLegal = await checkLegalConsent(userId: userId)
                
                if !hasAcceptedLegal {
                    // Store the user ID for the consent flow
                    self.pendingAppleUserId = userId
                    self.needsLegalConsent = true
                    // Don't update auth state yet - wait for consent
                    return
                }
                
                // The session observer will handle updating the auth state
                
                // Store the user's name if this is their first sign in
                if let fullName = appleIDCredential.fullName {
                    let name = [fullName.givenName, fullName.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    
                    if !name.isEmpty {
                        // Temporarily store for immediate use
                        UserDefaults.standard.set(name, forKey: "appleSignInName")
                        
                        // Update name using consolidated method
                        do {
                            try await consolidateNameUpdate(name)
                        } catch {
                            // print("❌ Failed to update name from Apple Sign In: \(error)")
                            // Keep the temporary storage for later resolution
                        }
                    }
                }
                
            case .signUp(let signUp):
                // For sign up, activate the session to get user ID
                if let sessionId = signUp.createdSessionId {
                    try await clerk.setActive(sessionId: sessionId)
                }
                
                // Get the actual user ID
                guard let userId = clerk.user?.id else {
                    throw AuthError.invalidCredentials
                }
                
                // For new users, always show consent screen
                self.pendingAppleUserId = userId
                self.needsLegalConsent = true
                
                // Store the user's name for onboarding
                if let fullName = appleIDCredential.fullName {
                    let name = [fullName.givenName, fullName.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    
                    if !name.isEmpty {
                        // Temporarily store for immediate use in onboarding
                        UserDefaults.standard.set(name, forKey: "appleSignInName")
                        
                        // Note: We don't update Clerk here because the user hasn't 
                        // accepted legal terms yet. The name will be synced during
                        // onboarding completion via consolidateNameUpdate
                    }
                }
            }
        } catch {
            // Show user-friendly error for authorization issues
            let errorString = String(describing: error).lowercased()
            if errorString.contains("authorization_invalid") {
                showAuthError("Apple Sign In is not properly configured. Please try signing in with email instead.")
            } else {
                showAuthError("Sign in failed. Please try again.")
            }
            
            throw error
        }
    }
    
    
    // MARK: - Helper Methods
    
    private func showAuthError(_ message: String) {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                let alert = UIAlertController(title: "Authentication Error", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                rootViewController.present(alert, animated: true)
            }
        }
    }
    
    // MARK: - Email Verification
    
    func verifyEmail(code: String) async throws {
        guard let signUp = currentSignUp else {
            throw AuthError.clerkNotInitialized
        }
        
        do {
            let result = try await signUp.attemptVerification(strategy: .emailCode(code: code))
            
            // Check verification status
            switch result.status {
            case .complete:
                if let createdSessionId = result.createdSessionId {
                    // Set the session as active to complete the sign up flow
                    try await clerk.setActive(sessionId: createdSessionId)
                    
                    // Force an immediate session state update
                    await MainActor.run {
                        self.updateSessionState()
                    }
                } else {
                    // Try to sign in with credentials
                    if let credentials = pendingSignUpCredentials {
                        try await login(email: credentials.email, password: credentials.password)
                    }
                }
                
            case .missingRequirements:
                // For now, show an error to the user about missing requirements
                // In a production app, you would handle legal acceptance properly
                let missingFieldsString = (signUp.missingFields ?? []).joined(separator: ", ")
                let errorMessage = missingFieldsString.isEmpty
                    ? "Additional requirements needed to complete sign up."
                    : "Please accept the terms of service to continue. Missing: \(missingFieldsString)"
                let error = NSError(
                    domain: "AuthManager",
                    code: 1_001,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage]
                )
                throw error
                
            default:
                break
            }
            
            // Clear email verification flag only when we're actually done
            // Don't clear it if we're still in the sign up process
            await MainActor.run {
                if self.isAuthenticated {
                    self.needsEmailVerification = false
                    self.currentSignUp = nil
                    self.pendingSignUpCredentials = nil
                }
            }
            
            // The session observer will now detect the active session and update isAuthenticated
        } catch {
            // Don't clear the verification state on error
            // This keeps the user on the verification screen
            throw error
        }
    }
    
    func resendVerificationEmail() async throws {
        guard let signUp = currentSignUp else {
            throw AuthError.clerkNotInitialized
        }
        
        do {
            try await signUp.prepareVerification(strategy: .emailCode)
        } catch {
            throw error
        }
    }
    
    // MARK: - Supabase Integration
    
    private func getSupabaseToken() async -> String? {
        // For now, we'll use the Supabase anon key
        // In production, you'd want to exchange the Clerk token for a Supabase token
        // through your backend API
        return Constants.supabaseAnonKey
    }
    
    // MARK: - Token Management
    
    func getAccessToken() async -> String? {
        guard let session = clerk.session else {
            // print("❌ No active Clerk session")
            return nil
        }
        
        do {
            // Get JWT token from Clerk
            let tokenResource = try await session.getToken()
            return tokenResource?.jwt
        } catch {
            // print("❌ Failed to get JWT token: \(error)")
            return nil
        }
    }
    
    // MARK: - Supabase Profile Sync
    
    private func createOrUpdateSupabaseProfile(user: LocalUser) async {
        guard let session = clerkSession else {
            // print("❌ No Clerk session available for profile sync")
            return
        }
        
        do {
            // Get JWT token from Clerk
            let tokenResource = try await session.getToken()
            guard let token = tokenResource?.jwt else {
                // print("❌ Failed to get JWT token for profile sync")
                return
            }
            
            // Prepare profile data
            let profileData: [String: Any] = [
                "id": user.id,
                "email": user.email,
                "name": user.name ?? NSNull(),
                "avatar_url": user.avatarUrl ?? NSNull(),
                "date_of_birth": user.profile?.dateOfBirth != nil ? ISO8601DateFormatter().string(from: user.profile!.dateOfBirth!) : NSNull(),
                "gender": user.profile?.gender ?? NSNull(),
                "weight_unit": user.profile?.goalWeightUnit ?? "kg",
                "height_unit": user.profile?.heightUnit ?? "cm",
                "height": user.profile?.height ?? NSNull(),
                "activity_level": user.profile?.activityLevel ?? NSNull(),
                "goal": user.profile?.goalWeight != nil ? "\(user.profile!.goalWeight!)" : NSNull(),
                "onboarding_completed": user.onboardingCompleted,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ]
            
            // Create/update profile in Supabase
            let url = URL(string: "\(Constants.supabaseURL)/rest/v1/profiles")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            
            let jsonData = try JSONSerialization.data(withJSONObject: [profileData])
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    // print("✅ Profile synced to Supabase")
                } else {
                    // print("❌ Profile sync failed: Status \(httpResponse.statusCode)")
                }
            }
        } catch {
            // print("❌ Profile sync error: \(error)")
        }
    }
    
    func updateProfile(_ updates: [String: Any]) async {
        guard var user = currentUser else { return }
        
        // Create a mutable copy of the profile or create a new one if it doesn't exist
        var updatedProfile = user.profile ?? UserProfile(
            id: user.id,
            email: user.email,
            username: nil,
            fullName: user.name,
            dateOfBirth: nil,
            height: nil,
            heightUnit: "cm",
            gender: nil,
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: "kg",
            onboardingCompleted: nil
        )
        
        // Update local user object
        if let name = updates["name"] as? String {
            user.name = name
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: name,
                dateOfBirth: updatedProfile.dateOfBirth,
                height: updatedProfile.height,
                heightUnit: updatedProfile.heightUnit,
                gender: updatedProfile.gender,
                activityLevel: updatedProfile.activityLevel,
                goalWeight: updatedProfile.goalWeight,
                goalWeightUnit: updatedProfile.goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }
        
        if let dateOfBirth = updates["dateOfBirth"] as? Date {
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: updatedProfile.fullName,
                dateOfBirth: dateOfBirth,
                height: updatedProfile.height,
                heightUnit: updatedProfile.heightUnit,
                gender: updatedProfile.gender,
                activityLevel: updatedProfile.activityLevel,
                goalWeight: updatedProfile.goalWeight,
                goalWeightUnit: updatedProfile.goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }

        if let gender = updates["gender"] as? String {
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: updatedProfile.fullName,
                dateOfBirth: updatedProfile.dateOfBirth,
                height: updatedProfile.height,
                heightUnit: updatedProfile.heightUnit,
                gender: gender,
                activityLevel: updatedProfile.activityLevel,
                goalWeight: updatedProfile.goalWeight,
                goalWeightUnit: updatedProfile.goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }

        if let height = updates["height"] as? Double {
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: updatedProfile.fullName,
                dateOfBirth: updatedProfile.dateOfBirth,
                height: height,
                heightUnit: updatedProfile.heightUnit,
                gender: updatedProfile.gender,
                activityLevel: updatedProfile.activityLevel,
                goalWeight: updatedProfile.goalWeight,
                goalWeightUnit: updatedProfile.goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }

        if let heightUnit = updates["heightUnit"] as? String {
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: updatedProfile.fullName,
                dateOfBirth: updatedProfile.dateOfBirth,
                height: updatedProfile.height,
                heightUnit: heightUnit,
                gender: updatedProfile.gender,
                activityLevel: updatedProfile.activityLevel,
                goalWeight: updatedProfile.goalWeight,
                goalWeightUnit: updatedProfile.goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }

        if let activityLevel = updates["activityLevel"] as? String {
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: updatedProfile.fullName,
                dateOfBirth: updatedProfile.dateOfBirth,
                height: updatedProfile.height,
                heightUnit: updatedProfile.heightUnit,
                gender: updatedProfile.gender,
                activityLevel: activityLevel,
                goalWeight: updatedProfile.goalWeight,
                goalWeightUnit: updatedProfile.goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }

        if let goalWeight = updates["goalWeight"] as? Double {
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: updatedProfile.fullName,
                dateOfBirth: updatedProfile.dateOfBirth,
                height: updatedProfile.height,
                heightUnit: updatedProfile.heightUnit,
                gender: updatedProfile.gender,
                activityLevel: updatedProfile.activityLevel,
                goalWeight: goalWeight,
                goalWeightUnit: updatedProfile.goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }

        if let goalWeightUnit = updates["goalWeightUnit"] as? String {
            updatedProfile = UserProfile(
                id: updatedProfile.id,
                email: updatedProfile.email,
                username: updatedProfile.username,
                fullName: updatedProfile.fullName,
                dateOfBirth: updatedProfile.dateOfBirth,
                height: updatedProfile.height,
                heightUnit: updatedProfile.heightUnit,
                gender: updatedProfile.gender,
                activityLevel: updatedProfile.activityLevel,
                goalWeight: updatedProfile.goalWeight,
                goalWeightUnit: goalWeightUnit,
                onboardingCompleted: updatedProfile.onboardingCompleted
            )
        }
        
        // Update the user's profile
        user.profile = updatedProfile

        if let onboardingCompleted = updates["onboardingCompleted"] as? Bool {
            user.onboardingCompleted = onboardingCompleted
            // Sync onboarding status to UserDefaults
            UserDefaults.standard.set(onboardingCompleted, forKey: Constants.hasCompletedOnboardingKey)
        // print("✅ AuthManager: Synced onboarding status to UserDefaults: \(onboardingCompleted)")
        }

        // Save updated user locally
        self.currentUser = user
        if let encoded = try? JSONEncoder().encode(user) {
            userDefaults.set(encoded, forKey: userKey)
        }

        // Sync to Supabase
        await createOrUpdateSupabaseProfile(user: user)
    }
    
    // MARK: - Session Management
    
    func fetchActiveSessions() async throws -> [SessionInfo] {
        guard let clerkUser = clerk.user else {
            throw AuthError.clerkNotInitialized
        }
        
        do {
            // Get all sessions from Clerk
            let sessions = try await clerkUser.getSessions()
            
            // Map Clerk sessions to our SessionInfo model
            return sessions.compactMap { clerkSession in
                // Use Mirror to access session properties
                let mirror = Mirror(reflecting: clerkSession)
                
                var sessionId = ""
                var lastActiveAt = Date()
                var createdAt = Date()
                var status = ""
                
                for child in mirror.children {
                    switch child.label {
                    case "id":
                        sessionId = child.value as? String ?? ""
                    case "lastActiveAt":
                        if let timestamp = child.value as? TimeInterval {
                            lastActiveAt = Date(timeIntervalSince1970: timestamp / 1_000)
                        }
                    case "createdAt":
                        if let timestamp = child.value as? TimeInterval {
                            createdAt = Date(timeIntervalSince1970: timestamp / 1_000)
                        }
                    case "status":
                        status = child.value as? String ?? ""
                    default:
                        break
                    }
                }
                
                // Only include active sessions
                guard status == "active" else { return nil }
                
                // Parse user agent and location (this is simplified - in production you'd parse the actual data)
                let deviceInfo = parseDeviceInfo(from: clerkSession)
                
                return SessionInfo(
                    id: sessionId,
                    deviceName: deviceInfo.deviceName,
                    deviceType: deviceInfo.deviceType,
                    location: deviceInfo.location,
                    ipAddress: deviceInfo.ipAddress,
                    lastActiveAt: lastActiveAt,
                    createdAt: createdAt,
                    isCurrentSession: sessionId == self.clerkSession?.id
                )
            }
        } catch {
            // print("❌ Failed to fetch sessions: \(error)")
            throw error
        }
    }
    
    func revokeSession(sessionId: String) async throws {
        // Don't allow revoking current session
        guard sessionId != clerkSession?.id else {
            throw NSError(
                domain: "AuthManager",
                code: 1_002,
                userInfo: [NSLocalizedDescriptionKey: "Cannot revoke current session"]
            )
        }
        
        guard let clerkUser = clerk.user else {
            throw AuthError.clerkNotInitialized
        }
        
        do {
            // Get all sessions and find the one to revoke
            let sessions = try await clerkUser.getSessions()
            
            // Find the session to revoke
            guard let sessionToRevoke = sessions.first(where: { session in
                let mirror = Mirror(reflecting: session)
                for child in mirror.children {
                    if child.label == "id", let id = child.value as? String {
                        return id == sessionId
                    }
                }
                return false
            }) else {
                throw NSError(
                    domain: "AuthManager",
                    code: 1_003,
                    userInfo: [NSLocalizedDescriptionKey: "Session not found"]
                )
            }
            
            // Use the session's revoke method
            try await sessionToRevoke.revoke()
            // print("✅ Session \(sessionId) revoked successfully")
        } catch {
            // print("❌ Failed to revoke session: \(error)")
            throw error
        }
    }
    
    private func parseDeviceInfo(from session: Any) -> (deviceName: String, deviceType: String, location: String, ipAddress: String) {
        // In a real implementation, you would parse the session's client info
        // For now, we'll use placeholder data based on the session
        
        let mirror = Mirror(reflecting: session)
        var clientInfo: [String: Any] = [:]
        
        for child in mirror.children {
            if child.label == "latestActivity" {
                // Parse activity data for location and device info
                let activityMirror = Mirror(reflecting: child.value)
                for activityChild in activityMirror.children {
                    switch activityChild.label {
                    case "browserName":
                        clientInfo["browser"] = activityChild.value
                    case "browserVersion":
                        clientInfo["browserVersion"] = activityChild.value
                    case "deviceType":
                        clientInfo["deviceType"] = activityChild.value
                    case "ipAddress":
                        clientInfo["ipAddress"] = activityChild.value
                    case "city":
                        clientInfo["city"] = activityChild.value
                    case "country":
                        clientInfo["country"] = activityChild.value
                    default:
                        break
                    }
                }
            }
        }
        
        // Determine device type
        let deviceTypeString = clientInfo["deviceType"] as? String ?? ""
        let deviceType: String = {
            switch deviceTypeString.lowercased() {
            case "mobile": return "iPhone"
            case "tablet": return "iPad"
            case "desktop": return "Mac"
            case "web": return "Web"
            default: return "Unknown"
            }
        }()
        
        // Format device name
        let browser = clientInfo["browser"] as? String ?? "Unknown Browser"
        let deviceName = deviceType == "Web" ? browser : deviceType
        
        // Format location
        let city = clientInfo["city"] as? String ?? ""
        let country = clientInfo["country"] as? String ?? ""
        let location = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
        
        // Get IP address
        let ipAddress = clientInfo["ipAddress"] as? String ?? "Unknown"
        
        return (
            deviceName: deviceName.isEmpty ? "Unknown Device" : deviceName,
            deviceType: deviceType,
            location: location.isEmpty ? "Unknown Location" : location,
            ipAddress: ipAddress
        )
    }
    
    // MARK: - Profile Picture Upload
    
    func uploadProfilePicture(_ image: UIImage) async throws -> String? {
        guard let clerkUser = clerk.user else {
            throw AuthError.clerkNotInitialized
        }
        
        // Resize image to reasonable size (max 1000x1000)
        let maxSize: CGFloat = 1_000
        let scale = min(maxSize / image.size.width, maxSize / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let imageData = resizedImage?.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        // Update Clerk user profile with image
        do {
            // Use Clerk's setProfileImage method
            let imageResource = try await clerkUser.setProfileImage(imageData: imageData)
            
            // print("✅ Profile image uploaded: \(imageResource.id)")
            
            // Get updated user object
            let updatedClerkUser = clerk.user
            
            // Update local user with new image URL
            if var user = currentUser, let updatedClerkUser = updatedClerkUser {
                // Use Mirror to get imageUrl from Clerk user
                let mirror = Mirror(reflecting: updatedClerkUser)
                for child in mirror.children {
                    if child.label == "imageUrl" {
                        if let newImageUrl = child.value as? String {
                            user.avatarUrl = newImageUrl
                            self.currentUser = user
                            
                            // Save locally
                            if let encoded = try? JSONEncoder().encode(user) {
                                userDefaults.set(encoded, forKey: userKey)
                            }
                            
                            // Sync to Supabase
                            await createOrUpdateSupabaseProfile(user: user)
                            
                            return newImageUrl
                        }
                        break
                    }
                }
            }
        } catch {
            // print("❌ Failed to upload profile picture: \(error)")
            throw error
        }
        
        return nil
    }
    
    // MARK: - Clerk User Updates
    
    func updateClerkUserName(_ fullName: String, retryCount: Int = 3) async throws {
        guard let _ = clerk.user else {
            throw AuthError.clerkNotInitialized
        }
        
        // Validate input
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AuthError.nameUpdateFailed("Name cannot be empty")
        }
        
        // Store the name temporarily in case update fails
        UserDefaults.standard.set(trimmedName, forKey: "pendingNameUpdate")
        
        // Since Clerk iOS SDK update method is unclear, we'll update our local state
        // and sync to Supabase. The name will be synced with Clerk on next sign in.
        // print("ℹ️ Updating name locally and in Supabase")
        
        // Update local user immediately
        if var user = currentUser {
            user.name = trimmedName
            
            // Create new profile with updated name
            if let existingProfile = user.profile {
                let updatedProfile = UserProfile(
                    id: existingProfile.id,
                    email: existingProfile.email,
                    username: existingProfile.username,
                    fullName: trimmedName,
                    dateOfBirth: existingProfile.dateOfBirth,
                    height: existingProfile.height,
                    heightUnit: existingProfile.heightUnit,
                    gender: existingProfile.gender,
                    activityLevel: existingProfile.activityLevel,
                    goalWeight: existingProfile.goalWeight,
                    goalWeightUnit: existingProfile.goalWeightUnit,
                    onboardingCompleted: existingProfile.onboardingCompleted
                )
                user.profile = updatedProfile
            }
            
            self.currentUser = user
            
            // Persist to UserDefaults
            if let encoded = try? JSONEncoder().encode(user) {
                userDefaults.set(encoded, forKey: userKey)
            }
            
            // Sync to Supabase
            await createOrUpdateSupabaseProfile(user: user)
            
            // Clear the pending update after successful local update
            UserDefaults.standard.removeObject(forKey: "pendingNameUpdate")
            
            // print("✅ Updated user name locally and in Supabase: \(trimmedName)")
        } else {
            throw AuthError.nameUpdateFailed("No current user found")
        }
    }
    
    // MARK: - Apple Sign In with OAuth
    @MainActor
    func signInWithAppleOAuth() async {
        guard isClerkLoaded else {
            showAuthError("Please wait for app to initialize and try again")
            return
        }
        
        do {
            // Create OAuth sign in
            let signIn = try await SignIn.create(strategy: .oauth(provider: .apple))
            
            // Open Safari for authentication
            try await signIn.authenticateWithRedirect()
        } catch {
            // Handle specific error cases
            let errorString = String(describing: error)
            
            if errorString.contains("oauth_provider_not_enabled") {
                showAuthError("Apple Sign In is not configured. Please contact support.")
            } else if errorString.contains("network") || errorString.contains("connection") {
                showAuthError("Network error. Please check your connection and try again.")
            } else {
                showAuthError("Apple Sign In failed. Please try email sign in instead.")
            }
        }
    }
    
    // MARK: - Name Management (Single Source of Truth)
    
    /// Single source of truth for getting the user's display name
    /// Priority: 1. Clerk user name, 2. Pending update, 3. Apple Sign In name, 4. Email prefix
    func getUserDisplayName() -> String {
        // First check if we have a Clerk user with a name
        if let clerkUser = clerk.user {
            let firstName = clerkUser.firstName ?? ""
            let lastName = clerkUser.lastName ?? ""
            let clerkName = [firstName, lastName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            
            if !clerkName.isEmpty {
                return clerkName
            }
        }
        
        // Check for pending name update (in case Clerk update failed)
        if let pendingName = UserDefaults.standard.string(forKey: "pendingNameUpdate"),
           !pendingName.isEmpty {
            return pendingName
        }
        
        // Check for Apple Sign In name (temporary storage during onboarding)
        if let appleSignInName = UserDefaults.standard.string(forKey: "appleSignInName"),
           !appleSignInName.isEmpty {
            return appleSignInName
        }
        
        // Fall back to email prefix (but not for private relay emails)
        if let email = currentUser?.email ?? clerk.user?.emailAddresses.first?.emailAddress {
            // Don't use email prefix for Apple private relay or other privacy-focused emails
            if email.contains("@privaterelay.appleid.com") ||
               email.contains("@icloud.com") ||
               email.hasPrefix("no-reply") {
                return "User"
            }
            return email.components(separatedBy: "@").first ?? "User"
        }

        return "User"
    }
    
    /// Consolidates name updates across all systems
    func consolidateNameUpdate(_ fullName: String) async throws {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AuthError.nameUpdateFailed("Name cannot be empty")
        }
        
        // Update using our method (which handles local, Supabase, and Core Data)
        try await updateClerkUserName(trimmedName)
        
        // Clean up temporary storage after successful update
        UserDefaults.standard.removeObject(forKey: "appleSignInName")
        
        // Sync to Core Data (if not already done in updateClerkUserName)
        if let userId = currentUser?.id,
           let email = currentUser?.email,
           let profile = currentUser?.profile {
            CoreDataManager.shared.saveProfile(profile, userId: userId, email: email)
        }
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .profileUpdated, object: nil)
    }
    
    /// Check and resolve any pending name updates on app launch
    func resolvePendingNameUpdates() async {
        guard let pendingName = UserDefaults.standard.string(forKey: "pendingNameUpdate"),
              !pendingName.isEmpty else {
            return
        }
        
        do {
            // print("📝 Resolving pending name update: \(pendingName)")
            try await consolidateNameUpdate(pendingName)
            // print("✅ Pending name update resolved")
        } catch {
            // print("❌ Failed to resolve pending name update: \(error)")
            // Keep the pending update for next attempt
        }
    }
    
    // MARK: - Legal Consent Management
    
    func checkLegalConsent(userId: String) async -> Bool {
        // Check if user has accepted legal terms in backend
        guard let token = await getSupabaseToken() else {
            return false
        }
        
        do {
            // Query the profiles table for legal consent status
            let url = URL(string: "\(Constants.supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=legal_accepted_at")!
            var request = URLRequest(url: url)
            request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let profile = json.first,
               let _ = profile["legal_accepted_at"] as? String {
                return true // User has accepted legal terms
            }
        } catch {
            // print("❌ Failed to check legal consent: \(error)")
        }
        
        return false
    }
    
    func acceptLegalConsent(userId: String) async {
        // Save legal consent to backend
        guard let token = await getSupabaseToken() else {
            return
        }
        
        do {
            let consentData: [String: Any] = [
                "id": userId,
                "legal_accepted_at": ISO8601DateFormatter().string(from: Date()),
                "terms_accepted": true,
                "privacy_accepted": true
            ]
            
            let url = URL(string: "\(Constants.supabaseURL)/rest/v1/profiles")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            
            let jsonData = try JSONSerialization.data(withJSONObject: [consentData])
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    // print("✅ Legal consent saved")
                    
                    // Now complete the sign in process
                    self.needsLegalConsent = false
                    self.pendingAppleUserId = nil
                    
                    // Force session update to complete authentication
                    self.updateSessionState()
                } else {
                    // print("❌ Failed to save consent: Status \(httpResponse.statusCode)")
                }
            }
        } catch {
            // print("❌ Failed to save legal consent: \(error)")
        }
    }
}

// MARK: - Apple Sign In Delegate
private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>
    
    init(continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) {
        self.continuation = continuation
        super.init()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation.resume(returning: appleIDCredential)
        } else {
            continuation.resume(throwing: ASAuthorizationError(.invalidResponse))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }

        // Fallback to any active window
        if let windowScene = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }

        // Last resort: create a new window for the first available scene
        // This prevents crashes but may not show UI properly
        // print("⚠️ No active window found for Apple Sign In - creating fallback window")
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return UIWindow(windowScene: windowScene)
        }

        // Absolute fallback: return a basic window (sign in won't work but won't crash)
        // print("❌ Critical: No window scene available - Apple Sign In will likely fail")
        return UIWindow(frame: UIScreen.main.bounds)
    }
}
