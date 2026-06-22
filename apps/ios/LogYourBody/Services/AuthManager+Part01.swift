import Combine
import AuthenticationServices
import UIKit
import CryptoKit
import Clerk

extension AuthManager {
var pendingVerificationEmail: String? {
        pendingSignUpEmail ?? pendingSignInEmail
    }

@discardableResult
    nonisolated static func migrateLegacyAuthStorage(in defaults: UserDefaults = .standard) -> [String] {
        var removedKeys: [String] = []

        for key in legacySensitiveUserDefaultsKeys {
            guard defaults.object(forKey: key) != nil else { continue }
            defaults.removeObject(forKey: key)
            removedKeys.append(key)
        }

        return removedKeys
    }

func migrateLegacyAuthToken() {
        _ = Self.migrateLegacyAuthStorage(in: userDefaults)

        #if DEBUG
        let remainingKeys = Self.legacySensitiveUserDefaultsKeys.filter {
            userDefaults.object(forKey: $0) != nil
        }

        if !remainingKeys.isEmpty {
            assertionFailure("Legacy auth/session values remain in UserDefaults: \(remainingKeys.joined(separator: ", "))")
        }
        #endif
    }

func showAuthError(_ message: String) {
        logAuthDiagnostic("show_error")
        clerkInitError = message
    }

func applySignedOutUITestFixture() {
        currentUser = nil
        clerkSession = nil
        isAuthenticated = false
        isClerkLoaded = true
        clerkInitError = nil
        needsLegalConsent = false
        lastExitReason = .none
        memberSinceDate = nil
        pendingAppleUserId = nil
        currentSignIn = nil
        currentSignUp = nil
        pendingSignInEmail = nil
        pendingSignUpEmail = nil
        emailVerificationFlow = nil
        needsEmailVerification = false
    }

func applyEmailVerificationUITestFixture(
        email: String = "otp-ready-ui@example.com",
        flow: EmailVerificationFlow = .signIn
    ) {
        applySignedOutUITestFixture()

        switch flow {
        case .signIn:
            pendingSignInEmail = email
        case .signUp:
            pendingSignUpEmail = email
        }

        emailVerificationFlow = flow
        needsEmailVerification = true
    }

func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

nonisolated static func normalizedAuthEmailCandidate(_ value: String?) -> String? {
        let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard candidate.contains("@"),
              !candidate.contains(" ") else {
            return nil
        }

        return candidate
    }

nonisolated static func syntheticAuthEmail(userId: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = userId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
        let localPart = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))

        guard !localPart.isEmpty else {
            return nil
        }

        return "\(localPart)@apple.local.logyourbody"
    }

func logAuthDiagnostic(_ stage: String, details: [String: String] = [:]) {
        let summary = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let suffix = summary.isEmpty ? "" : " \(summary)"

        AppLogger.auth.info("LYB_AUTH \(stage)\(suffix)")
    }

func logSessionDiagnostic(_ stage: String, expectedSessionId: String? = nil) {
        let session = clerk.session
        let identifier = session?.publicUserData?.identifier ?? ""
        let matchesExpectedSession = expectedSessionId.map { session?.id == $0 } ?? false

        logAuthDiagnostic(
            stage,
            details: [
                "hasSession": boolString(session != nil),
                "hasUser": boolString(clerk.user != nil),
                "hasPublicUserData": boolString(session?.publicUserData != nil),
                "identifierLooksEmail": boolString(identifier.contains("@")),
                "isAuthenticated": boolString(isAuthenticated),
                "sessionMatchesExpected": boolString(matchesExpectedSession)
            ]
        )
    }

func updateClerkUserName(_ name: String) async throws {
        // Store pending name locally; full Clerk profile sync is handled elsewhere.
        UserDefaults.standard.set(name, forKey: "pendingNameUpdate")
    }

func handleSupabaseUnauthorized() async {
        await performLogout(exitReason: .sessionExpired)
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

        let environmentValidation = Configuration.currentAuthEnvironmentValidation
        guard environmentValidation.isValid else {
            let error = environmentValidation.userMessage
            await MainActor.run {
                self.isClerkLoaded = false
                self.clerkInitError = error
            }
            return
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
            // print("✅ Clerk SDK loaded successfully in \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")

            await MainActor.run {
                self.isClerkLoaded = true
                self.clerkInitError = nil
                self.observeSessionChanges()
            }
        } catch {
            let errorMessage = error.localizedDescription
            let context = ErrorContext(
                feature: "auth",
                operation: "initializeClerk",
                screen: nil,
                userId: nil
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
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

@discardableResult
    func ensureClerkInitializationTask(priority: TaskPriority = .userInitiated) -> Task<Void, Never> {
        if let existingTask = clerkInitializationTask, !existingTask.isCancelled {
            return existingTask
        }

        let task = Task(priority: priority) { [weak self] in
            guard let self else { return }
            await self.initializeClerk()
        }

        clerkInitializationTask = task
        return task
    }

/// Retry Clerk initialization after a failure
    func retryClerkInitialization() async {
        // print("🔄 Retrying Clerk initialization...")
        clerkInitializationTask?.cancel()
        clerkInitializationTask = nil

        let task = ensureClerkInitializationTask()
        await task.value
    }

func observeSessionChanges() {
        // Cancel any existing observation
        sessionObservationTask?.cancel()

        // Clear any existing timer subscriptions before creating a new one
        cancellables.removeAll()

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
    func updateSessionState(force: Bool = false) {
        _ = clerk.session != nil
        let previousSessionId = self.clerkSession?.id
        let currentSessionId = clerk.session?.id

        // Update when the session changes, or when a newly-active Clerk session
        // has not yet been projected into the app's local auth state.
        if force || previousSessionId != currentSessionId || (currentSessionId != nil && currentUser == nil) {
            // print("🔄 Session change detected: \(previousSessionId ?? "nil") -> \(currentSessionId ?? "nil")")

            self.clerkSession = clerk.session

            if clerk.session != nil, let user = clerk.user, self.updateLocalUser(clerkUser: user) {
                // Only authenticate if we have both a valid session AND user
                // print("🔄 Clerk session state: signed in with user \(user.id)")
                // isAuthenticated will be set by updateLocalUser if successful

                // Clear any remaining sign-up/sign-in state
                self.currentSignUp = nil
                self.pendingSignUpEmail = nil
                self.currentSignIn = nil
                self.pendingSignInEmail = nil
                self.needsEmailVerification = false
                self.emailVerificationFlow = nil

                // Notify RevenueCat of authenticated user for correct entitlement handling
                if let localUserId = self.currentUser?.id {
                    Task {
                        await RevenueCatManager.shared.identifyUser(userId: localUserId)
                    }
                }

                Task { @MainActor in
                    await self.bootstrapAuthenticatedProfileIfNeeded(sessionId: currentSessionId)
                }
            } else if let session = clerk.session, updateLocalUser(clerkSession: session) {
                self.currentSignUp = nil
                self.pendingSignUpEmail = nil
                self.currentSignIn = nil
                self.pendingSignInEmail = nil
                self.needsEmailVerification = false
                self.emailVerificationFlow = nil

                if let localUserId = self.currentUser?.id {
                    Task {
                        await RevenueCatManager.shared.identifyUser(userId: localUserId)
                    }
                }

                Task { @MainActor in
                    await self.bootstrapAuthenticatedProfileIfNeeded(sessionId: currentSessionId)
                }
            } else {
                // No valid session or user
                // print("🔄 Clerk session state: signed out")
                if previousSessionId != nil && currentSessionId == nil && lastExitReason == .none {
                    lastExitReason = .sessionExpired
                    Task {
                        await self.performLogout(exitReason: .sessionExpired)
                    }
                    return
                }
                self.isAuthenticated = false
                self.currentUser = nil
                self.bootstrappedProfileSessionIds.removeAll()
                userDefaults.removeObject(forKey: userKey)
                ErrorTrackingService.shared.updateUserId(nil)
                AnalyticsService.shared.reset()
                Task {
                    await RevenueCatManager.shared.logoutUser()
                }
            }
        }
    }

// MARK: - Session Management

    func fetchActiveSessions() async throws -> [SessionInfo] {
        guard let session = clerk.session else {
            return []
        }

        let deviceName = UIDevice.current.name
        #if os(iOS)
        let deviceType = "iPhone"
        #else
        let deviceType = "Unknown"
        #endif

        let now = Date()

        let info = SessionInfo(
            id: session.id,
            deviceName: deviceName,
            deviceType: deviceType,
            location: "Unknown",
            ipAddress: "",
            lastActiveAt: now,
            createdAt: now,
            isCurrentSession: true
        )

        return [info]
    }

func changePassword(currentPassword: String, newPassword: String) async throws {
        do {
            try await accountAdapter.updatePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
        } catch let error as PasswordUpdateError {
            throw error
        } catch let clerkError as ClerkAPIError {
            switch clerkError.code {
            case "form_password_incorrect":
                throw PasswordUpdateError.incorrectCurrentPassword
            case "form_password_not_strong_enough":
                throw PasswordUpdateError.notStrongEnough
            default:
                throw PasswordUpdateError.failed(clerkError.message ?? "Failed to update password")
            }
        } catch {
            throw PasswordUpdateError.failed(error.localizedDescription)
        }
    }

func deleteCurrentAccount() async throws {
        try await accountAdapter.deleteCurrentAccount()
    }

@discardableResult
    func updateLocalUser(clerkSession session: Session) -> Bool {
        guard let publicUserData = session.publicUserData,
              let userId = publicUserData.userId else {
            return false
        }

        let email = Self.normalizedAuthEmailCandidate(publicUserData.identifier)
            ?? Self.syntheticAuthEmail(userId: userId)

        guard let email else {
            logAuthDiagnostic("local_user_projection_failed", details: ["source": "session"])
            return false
        }

        let name = [
            publicUserData.firstName,
            publicUserData.lastName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        applyLocalUser(
            userId: userId,
            email: email,
            username: nil,
            imageUrl: publicUserData.imageUrl.isEmpty ? nil : publicUserData.imageUrl,
            displayName: name.isEmpty ? getUserDisplayName() : name
        )

        return true
    }

func revokeSession(sessionId: String) async throws {
        do {
            try await clerk.signOut(sessionId: sessionId)
        } catch {
            throw error
        }

        if clerk.session == nil || clerk.session?.id == sessionId {
            await performLogout(exitReason: .sessionExpired)
        }
    }

@discardableResult
    func updateLocalUser(clerkUser: Any) -> Bool {
        // Use Mirror to access properties dynamically due to type naming conflict
        let mirror = Mirror(reflecting: clerkUser)

        // Extract properties using Mirror
        var userId = ""
        var emailAddresses: [Any] = []
        var externalAccounts: [Any] = []
        var username: String?
        var imageUrl: String?

        for child in mirror.children {
            switch child.label {
            case "id":
                userId = child.value as? String ?? ""
            case "emailAddresses":
                emailAddresses = child.value as? [Any] ?? []
            case "externalAccounts":
                externalAccounts = child.value as? [Any] ?? []
            case "username":
                username = child.value as? String
            case "imageUrl":
                imageUrl = child.value as? String
            default:
                break
            }
        }

        let email = firstEmailAddress(in: emailAddresses)
            ?? firstEmailAddress(in: externalAccounts)
            ?? Self.syntheticAuthEmail(userId: userId)
            ?? ""

        return applyLocalUser(
            userId: userId,
            email: email,
            username: username,
            imageUrl: imageUrl,
            displayName: getUserDisplayName()
        )
    }

func firstEmailAddress(in values: [Any]) -> String? {
        for value in values {
            let mirror = Mirror(reflecting: value)

            for child in mirror.children where child.label == "emailAddress" {
                if let email = Self.normalizedAuthEmailCandidate(child.value as? String) {
                    return email
                }
            }
        }

        return nil
    }

@discardableResult
    func applyLocalUser(
        userId: String,
        email: String,
        username: String?,
        imageUrl: String?,
        displayName: String
    ) -> Bool {
        guard !userId.isEmpty, !email.isEmpty else {
            self.currentUser = nil
            self.isAuthenticated = false
            return false
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
        self.lastExitReason = .none

        ErrorTrackingService.shared.updateUserId(localUser.id)
        var traits: [String: String] = [
            "email": email,
            "name": localUser.displayName,
            "platform": "ios",
            "app_version": AppVersion.current,
            "build_number": AppVersion.build,
            "environment": Configuration.sentryEnvironment
        ]

        if let username, !username.isEmpty {
            traits["username"] = username
        }

        if let imageUrl, !imageUrl.isEmpty {
            traits["has_avatar"] = "true"
        }

        if let profile = localUser.profile,
           let fullName = profile.fullName,
           !fullName.isEmpty {
            traits["full_name"] = fullName
        }

        AnalyticsService.shared.identify(
            userId: localUser.id,
            properties: traits
        )

        return true
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

        // Real authentication uses an email one-time code via Clerk.
        try await startEmailCodeSignIn(email: email)
    }

func startEmailCodeSignIn(email: String) async throws {
        guard isClerkLoaded else {
            throw AuthError.clerkNotInitialized
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw AuthError.invalidCredentials
        }

        let signIn = try await SignIn.create(
            strategy: .identifier(trimmedEmail, strategy: .emailCode())
        )

        currentSignIn = signIn
        pendingSignInEmail = trimmedEmail
        emailVerificationFlow = .signIn
        needsEmailVerification = true
    }
}
