import Foundation
import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

@MainActor
final class SubmissionStoreTests: XCTestCase {
    func testSQLiteReopenRestoresOwnerAndProgress() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.sqlite")
        let ownerA = UUID()
        let ownerB = UUID()
        let draftA = makeDraft(ownerID: ownerA)
        let draftB = makeDraft(ownerID: ownerB)

        do {
            let first = try await CoreDataSubmissionStore(storeURL: url)
            try await first.insertDraft(draftA)
            try await first.insertDraft(draftB)
            let lease = UUID()
            let claimedValue = try await first.claim(
                id: draftA.id, ownerID: ownerA, leaseOwner: lease,
                leaseExpiresAt: Date().addingTimeInterval(300)
            )
            let claimed = try XCTUnwrap(claimedValue)
            let queued = try XCTUnwrap(claimed.replacingProgress(
                state: .queued, resumeStage: .upload, remoteID: nil,
                attemptCount: 0, nextAttemptAt: nil, lastFailure: nil,
                leaseOwner: lease, leaseExpiresAt: claimed.leaseExpiresAt,
                updatedAt: Date()
            ))
            try await first.save(queued, leaseOwner: lease)
            try await first.release(id: draftA.id, ownerID: ownerA, leaseOwner: lease)
        }

        let reopened = try await CoreDataSubmissionStore(storeURL: url)
        let a = try await reopened.listPending(ownerID: ownerA)
        let b = try await reopened.listPending(ownerID: ownerB)
        XCTAssertEqual(a.map(\.id), [draftA.id])
        XCTAssertEqual(a.first?.state, .queued)
        XCTAssertEqual(a.first?.payloadData, draftA.payloadData)
        XCTAssertNil(a.first?.leaseOwner)
        XCTAssertEqual(b.map(\.id), [draftB.id])
        let hiddenRemoteID = try await reopened.completedRemoteID(for: draftA.id, ownerID: ownerB)
        XCTAssertNil(hiddenRemoteID)
    }

    func testClaimIsExclusiveAcrossStoreInstancesAndOwner() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.sqlite")
        let a = try await CoreDataSubmissionStore(storeURL: url)
        let b = try await CoreDataSubmissionStore(storeURL: url)
        let draft = makeDraft(ownerID: UUID())
        try await a.insertDraft(draft)
        let firstLease = UUID()
        let otherLease = UUID()
        let expiry = Date().addingTimeInterval(300)

        let first = try await a.claim(id: draft.id, ownerID: draft.ownerID,
                                      leaseOwner: firstLease, leaseExpiresAt: expiry)
        XCTAssertEqual(first?.leaseOwner, firstLease)
        let blockedByLease = try await b.claim(id: draft.id, ownerID: draft.ownerID,
                                               leaseOwner: otherLease, leaseExpiresAt: expiry)
        let blockedByOwner = try await b.claim(id: draft.id, ownerID: UUID(),
                                               leaseOwner: otherLease, leaseExpiresAt: expiry)
        XCTAssertNil(blockedByLease)
        XCTAssertNil(blockedByOwner)
        try await a.release(id: draft.id, ownerID: draft.ownerID, leaseOwner: firstLease)
        let second = try await b.claim(id: draft.id, ownerID: draft.ownerID,
                                       leaseOwner: otherLease, leaseExpiresAt: expiry)
        XCTAssertEqual(second?.leaseOwner, otherLease)

        let racing = makeDraft(ownerID: draft.ownerID)
        try await a.insertDraft(racing)
        async let aClaim = a.claim(id: racing.id, ownerID: racing.ownerID,
                                   leaseOwner: UUID(), leaseExpiresAt: expiry)
        async let bClaim = b.claim(id: racing.id, ownerID: racing.ownerID,
                                   leaseOwner: UUID(), leaseExpiresAt: expiry)
        let aResult = try await aClaim
        let bResult = try await bClaim
        XCTAssertEqual([aResult, bResult].compactMap { $0 }.count, 1)
    }

    func testExpiredLeaseCanBeReclaimedAndWrongLeaseCannotSave() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await CoreDataSubmissionStore(
            storeURL: directory.appendingPathComponent("queue.sqlite")
        )
        let draft = makeDraft(ownerID: UUID())
        try await store.insertDraft(draft)
        let expired = UUID()
        _ = try await store.claim(id: draft.id, ownerID: draft.ownerID,
                                  leaseOwner: expired, leaseExpiresAt: Date().addingTimeInterval(1))
        try await Task.sleep(for: .milliseconds(1_200))
        let current = UUID()
        let claimed = try await store.claim(id: draft.id, ownerID: draft.ownerID,
                                            leaseOwner: current,
                                            leaseExpiresAt: Date().addingTimeInterval(300))
        XCTAssertEqual(claimed?.leaseOwner, current)
        do {
            try await store.save(try XCTUnwrap(claimed), leaseOwner: expired)
            XCTFail("古いleaseで保存できてはいけません")
        } catch {
            XCTAssertTrue(error is SubmissionStoreError)
        }
    }

    func testCannotChangeImmutablePayloadWhileHoldingLease() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await CoreDataSubmissionStore(
            storeURL: directory.appendingPathComponent("queue.sqlite")
        )
        let draft = makeDraft(ownerID: UUID())
        try await store.insertDraft(draft)
        let lease = UUID()
        let claimedValue = try await store.claim(
            id: draft.id, ownerID: draft.ownerID, leaseOwner: lease,
            leaseExpiresAt: Date().addingTimeInterval(300)
        )
        let claimed = try XCTUnwrap(claimedValue)
        let forged = try XCTUnwrap(PendingSubmission(
            id: claimed.id, ownerID: claimed.ownerID, schemaVersion: 1,
            kind: .photo, payloadData: Data("changed".utf8),
            localFilePaths: claimed.localFilePaths, assetPaths: claimed.assetPaths,
            dependsOn: nil, remoteID: nil, state: .draft, resumeStage: .upload,
            attemptCount: 0, nextAttemptAt: nil, lastFailure: nil,
            leaseOwner: lease, leaseExpiresAt: claimed.leaseExpiresAt,
            createdAt: claimed.createdAt, updatedAt: claimed.updatedAt
        ))
        do {
            try await store.save(forged, leaseOwner: lease)
            XCTFail("保存済みpayloadを差し替えられてはいけません")
        } catch let error as SubmissionStoreError {
            XCTAssertEqual(error, .immutableFieldsChanged)
        }
    }

    private func makeDraft(ownerID: UUID) -> PendingSubmission {
        PendingSubmission(
            id: UUID(), ownerID: ownerID, schemaVersion: 1, kind: .photo,
            payloadData: Data("{\"caption\":\"draft\"}".utf8),
            localFilePaths: ["draft.png"], assetPaths: [], dependsOn: nil,
            remoteID: nil, state: .draft, resumeStage: .upload,
            attemptCount: 0, nextAttemptAt: nil, lastFailure: nil,
            leaseOwner: nil, leaseExpiresAt: nil,
            createdAt: Date(), updatedAt: Date()
        )!
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
