import Foundation

public protocol SubmissionStoring: Sendable {
    func insertDraft(_ submission: PendingSubmission) async throws
    func listPending(ownerID: UUID) async throws -> [PendingSubmission]
    func completedRemoteID(for dependencyID: UUID, ownerID: UUID) async throws -> UUID?
    func claim(
        id: UUID,
        ownerID: UUID,
        leaseOwner: UUID,
        leaseExpiresAt: Date
    ) async throws -> PendingSubmission?
    func save(_ submission: PendingSubmission, leaseOwner: UUID) async throws
    func release(id: UUID, ownerID: UUID, leaseOwner: UUID) async throws
}
