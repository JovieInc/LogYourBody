import Foundation

/// All account-owned presentation changes together when the account lifetime changes.
struct BodySpecIntegrationState {
    enum RecoveryAction { case connect, disconnect }
    private(set) var owner: AuthManager.ProfileSessionOwnership?
    var operationID = UUID()
    var isConnected = false
    var connectedEmail: String?
    var isConnecting = false
    var isSyncing = false
    var lastSyncSummary: String?
    var lastSyncFailed = false
    var errorMessage: String?
    var recoveryAction: RecoveryAction?
    var isLoadingScans = false
    var recentScans: [DexaResult] = []
    var recentScansError: String?

    mutating func reset(for owner: AuthManager.ProfileSessionOwnership?) {
        self = Self(owner: owner)
    }

    mutating func replaceConnectionOperation() -> UUID {
        operationID = UUID()
        isConnecting = false
        isSyncing = false
        isLoadingScans = false
        return operationID
    }

    func owns(_ operation: UUID, account: AuthManager.ProfileSessionOwnership) -> Bool {
        operationID == operation && owner == account
    }

    mutating func disconnectFailed() {
        errorMessage = "We couldn’t remove the saved BodySpec connection. Try disconnecting again."
        recoveryAction = .disconnect
    }
}
