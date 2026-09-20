import Foundation

public enum SubmissionState: String, Codable, Sendable {
    case draft
    case queued
    case uploading
    case registering
    case completed
    case retryWaiting
    case needsLogin
    case needsCorrection
    case outcomeUnknown
    case cancelled
}
