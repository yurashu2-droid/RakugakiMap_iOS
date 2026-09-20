import Foundation

public enum SafetyTargetKind: String, Codable, Sendable {
    case photo = "PHOTO"
    case rakugaki = "RAKUGAKI"
    case user = "USER"
}

public enum SafetyReportReason: String, Codable, Sendable, CaseIterable {
    case harassment = "HARASSMENT"
    case sexual = "SEXUAL"
    case violence = "VIOLENCE"
    case privacy = "PRIVACY"
    case spam = "SPAM"
    case other = "OTHER"
}

public struct SafetyReportReceipt: Equatable, Sendable {
    public let id: UUID
    public let receivedAt: Date
    public let status: String

    public init(id: UUID, receivedAt: Date, status: String) {
        self.id = id
        self.receivedAt = receivedAt
        self.status = status
    }
}

public struct BlockedUser: Equatable, Sendable {
    public let id: UUID
    public let uniqueID: String
    public let displayName: String
    public let blockedAt: Date

    public init(id: UUID, uniqueID: String, displayName: String, blockedAt: Date) {
        self.id = id
        self.uniqueID = uniqueID
        self.displayName = displayName
        self.blockedAt = blockedAt
    }
}
