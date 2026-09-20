import Foundation

public enum AppFailure: Error, Equatable, Sendable {
    case offline
    case needsLogin
    case forbidden
    case notFound
    case cancelled
    case validation(String)
    case rateLimited
    case outcomeUnknown
    case serviceUnavailable
}
