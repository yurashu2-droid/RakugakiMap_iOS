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

public enum SubmissionKind: String, Codable, Sendable {
    case photo
    case rakugaki
    case ar
    case groupAnswer
}

public enum SubmissionResumeStage: String, Codable, Sendable {
    case upload
    case register
    case none

    func isCompatible(with state: SubmissionState) -> Bool {
        switch state {
        case .draft, .queued, .retryWaiting, .needsLogin, .needsCorrection:
            return self == .upload || self == .register
        case .uploading:
            return self == .upload
        case .registering, .outcomeUnknown:
            return self == .register
        case .completed, .cancelled:
            return self == .none
        }
    }
}

public struct PendingSubmission: Equatable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let schemaVersion: Int
    public let kind: SubmissionKind
    public let payloadData: Data
    public let localFilePaths: [String]
    public let assetPaths: [AssetReference]
    public let dependsOn: UUID?
    public let createdAt: Date
    public let remoteID: UUID?
    public let state: SubmissionState
    public let resumeStage: SubmissionResumeStage
    public let attemptCount: Int
    public let nextAttemptAt: Date?
    public let lastFailure: AppFailure?
    public let leaseOwner: UUID?
    public let leaseExpiresAt: Date?
    public let updatedAt: Date

    public init?(
        id: UUID,
        ownerID: UUID,
        schemaVersion: Int,
        kind: SubmissionKind,
        payloadData: Data,
        localFilePaths: [String],
        assetPaths: [AssetReference],
        dependsOn: UUID?,
        remoteID: UUID?,
        state: SubmissionState,
        resumeStage: SubmissionResumeStage,
        attemptCount: Int,
        nextAttemptAt: Date?,
        lastFailure: AppFailure?,
        leaseOwner: UUID?,
        leaseExpiresAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        guard schemaVersion > 0,
              !payloadData.isEmpty,
              !localFilePaths.contains(where: {
                  $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              dependsOn != id,
              attemptCount >= 0,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              createdAt <= updatedAt,
              (nextAttemptAt?.timeIntervalSinceReferenceDate.isFinite ?? true),
              (leaseExpiresAt?.timeIntervalSinceReferenceDate.isFinite ?? true),
              (leaseOwner == nil) == (leaseExpiresAt == nil),
              resumeStage.isCompatible(with: state),
              state != .completed || remoteID != nil else {
            return nil
        }

        self.id = id
        self.ownerID = ownerID
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.payloadData = payloadData
        self.localFilePaths = localFilePaths
        self.assetPaths = assetPaths
        self.dependsOn = dependsOn
        self.createdAt = createdAt
        self.remoteID = remoteID
        self.state = state
        self.resumeStage = resumeStage
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastFailure = lastFailure
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.updatedAt = updatedAt
    }

    public func replacingProgress(
        state: SubmissionState,
        resumeStage: SubmissionResumeStage,
        remoteID: UUID?,
        attemptCount: Int,
        nextAttemptAt: Date?,
        lastFailure: AppFailure?,
        leaseOwner: UUID?,
        leaseExpiresAt: Date?,
        updatedAt: Date
    ) -> PendingSubmission? {
        guard attemptCount >= self.attemptCount,
              updatedAt >= self.updatedAt,
              !(self.resumeStage == .register && resumeStage == .upload),
              self.remoteID == nil || self.remoteID == remoteID else {
            return nil
        }
        return PendingSubmission(
            id: id,
            ownerID: ownerID,
            schemaVersion: schemaVersion,
            kind: kind,
            payloadData: payloadData,
            localFilePaths: localFilePaths,
            assetPaths: assetPaths,
            dependsOn: dependsOn,
            remoteID: remoteID,
            state: state,
            resumeStage: resumeStage,
            attemptCount: attemptCount,
            nextAttemptAt: nextAttemptAt,
            lastFailure: lastFailure,
            leaseOwner: leaseOwner,
            leaseExpiresAt: leaseExpiresAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func isOwned(by context: SessionContext) -> Bool {
        ownerID == context.userID
    }
}
