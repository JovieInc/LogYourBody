import Foundation

enum AppErrorSeverity {
    case info
    case warning
    case error
    case critical
}

enum AppError: LocalizedError {
    case auth(AuthError)
    case supabase(SupabaseError)
    case photo(PhotoUploadManager.PhotoError)
    case healthKit(HealthKitError)
    case coreData(operation: String, underlying: Error?)
    case network(operation: String, underlying: Error?)
    case billing(operation: String, underlying: Error?)
    case unexpected(context: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .auth(let authError):
            return authError.errorDescription
        case .supabase(let supabaseError):
            return supabaseError.errorDescription
        case .photo(let photoError):
            return photoError.errorDescription
        case .healthKit(let hkError):
            return hkError.errorDescription
        case .coreData(let operation, _):
            return "A data error occurred while \(operation)."
        case .network(let operation, _):
            return "A network error occurred while \(operation). Please check your connection and try again."
        case .billing(let operation, _):
            return "A billing error occurred while \(operation). Please try again."
        case .unexpected:
            return "Something went wrong. Please try again."
        }
    }

    var severity: AppErrorSeverity {
        switch self {
        case .auth:
            return .error
        case .supabase:
            return .error
        case .photo:
            return .warning
        case .healthKit:
            return .warning
        case .coreData:
            return .critical
        case .network:
            return .warning
        case .billing:
            return .error
        case .unexpected:
            return .critical
        }
    }

    var isUserFacing: Bool {
        switch self {
        case .auth,
             .supabase,
             .photo,
             .healthKit,
             .coreData,
             .network,
             .billing:
            return true
        case .unexpected:
            return false
        }
    }
}

