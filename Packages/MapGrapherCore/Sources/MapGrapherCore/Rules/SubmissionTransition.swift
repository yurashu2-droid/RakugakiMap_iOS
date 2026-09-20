import Foundation

public enum SubmissionTransition: Sendable {
    public static func allows(
        from: SubmissionState,
        to: SubmissionState,
        requiresRemoteDependency: Bool,
        dependencyRemoteID: UUID?
    ) -> Bool {
        if requiresRemoteDependency && dependencyRemoteID == nil {
            switch to {
            case .uploading, .registering, .completed:
                return false
            default:
                break
            }
        }

        switch from {
        case .draft:
            switch to {
            case .queued, .cancelled: return true
            default: return false
            }
        case .queued:
            switch to {
            case .uploading, .needsLogin, .needsCorrection, .cancelled: return true
            default: return false
            }
        case .uploading:
            switch to {
            case .registering, .retryWaiting, .needsLogin,
                 .needsCorrection, .outcomeUnknown, .cancelled: return true
            default: return false
            }
        case .registering:
            switch to {
            case .completed, .retryWaiting, .needsLogin,
                 .needsCorrection, .outcomeUnknown, .cancelled: return true
            default: return false
            }
        case .retryWaiting:
            switch to {
            case .queued, .uploading, .registering,
                 .needsLogin, .needsCorrection, .cancelled: return true
            default: return false
            }
        case .needsLogin:
            switch to {
            case .queued, .uploading, .registering, .cancelled: return true
            default: return false
            }
        case .needsCorrection:
            return to == .cancelled
        case .outcomeUnknown:
            switch to {
            case .registering, .completed, .needsCorrection, .cancelled: return true
            default: return false
            }
        case .completed, .cancelled:
            return false
        }
    }
}
