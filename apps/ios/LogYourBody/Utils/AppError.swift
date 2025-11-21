import Foundation

enum AppError: LocalizedError {
    case auth(AuthError)
    case supabase(SupabaseError)
    case photo(PhotoUploadManager.PhotoError)
    case healthKit(HealthKitError)
    case coreData(operation: String, underlying: Error?)
    case network(operation: String, underlying: Error?)
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
        case .unexpected:
            return "Something went wrong. Please try again."
        }
    }
}
