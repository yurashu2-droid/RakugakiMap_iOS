import Foundation
import XCTest
@testable import MapGrapherCore

final class SubmissionCoordinatorTests: XCTestCase {
    func testSuccessfulUploadAndRegisterCompleteOnce() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let store = MemorySubmissionStore()
        let transport = FakeSubmissionTransport()
        let id = UUID()
        try await store.insertDraft(try makeDraft(id: id, owner: owner, payload: photoPayload()))
        let coordinator = SubmissionCoordinator(store: store, session: FakeSubmissionSession(context: context),
                                                transport: transport)
        try await coordinator.enqueue(draftID: id, context: context)
        let calls = await transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [id])
        let remoteID = await store.completedRemoteID(for: id, ownerID: owner)
        XCTAssertEqual(remoteID, id)
    }

    func testConcurrentResumeDoesNotStartSameOperationTwice() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let store = MemorySubmissionStore()
        let transport = FakeSubmissionTransport()
        await transport.setUploadDelay(.milliseconds(100))
        let id = UUID()
        let draft = try makeDraft(id: id, owner: owner, payload: photoPayload())
        let queued = draft.replacingProgress(state: .queued, resumeStage: .upload, remoteID: nil,
            attemptCount: 0, nextAttemptAt: nil, lastFailure: nil, leaseOwner: nil,
            leaseExpiresAt: nil, updatedAt: Date())!
        try await store.insertDraft(queued)
        let coordinator = SubmissionCoordinator(store: store, session: FakeSubmissionSession(context: context),
                                                transport: transport)
        async let first: Void = coordinator.resume(context: context)
        async let second: Void = coordinator.resume(context: context)
        _ = await (first, second)
        let calls = await transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [id])
    }

    func testLostRegisterResponseReusesRequestAndDoesNotUploadAgain() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let store = MemorySubmissionStore()
        let session = FakeSubmissionSession(context: context)
        let transport = FakeSubmissionTransport()
        let id = UUID()
        let payload = photoPayload()
        try await store.insertDraft(try makeDraft(id: id, owner: owner, payload: payload))
        await transport.setLoseFirstResponse()
        let coordinator = SubmissionCoordinator(store: store, session: session, transport: transport)
        try await coordinator.enqueue(draftID: id, context: context)
        try await Task.sleep(for: .seconds(3))
        await coordinator.resume(context: context)
        let calls = await transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [id, id])
        let remoteID = await store.completedRemoteID(for: id, ownerID: owner)
        XCTAssertEqual(remoteID, id)
    }

    func testLocalSaveFailureAfterServerSuccessReplaysRegistrationOnly() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let store = MemorySubmissionStore()
        await store.failNextCompletionSave()
        let transport = FakeSubmissionTransport()
        let id = UUID()
        try await store.insertDraft(try makeDraft(id: id, owner: owner, payload: photoPayload()))
        let coordinator = SubmissionCoordinator(store: store,
                                                session: FakeSubmissionSession(context: context),
                                                transport: transport)
        try await coordinator.enqueue(draftID: id, context: context)
        await coordinator.resume(context: context)
        let calls = await transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [id, id])
        let remoteID = await store.completedRemoteID(for: id, ownerID: owner)
        XCTAssertEqual(remoteID, id)
    }

    func testAccountSwitchStopsBeforeRegistration() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let store = MemorySubmissionStore()
        let session = FakeSubmissionSession(context: context)
        let transport = FakeSubmissionTransport()
        let id = UUID()
        let payload = photoPayload()
        try await store.insertDraft(try makeDraft(id: id, owner: owner, payload: payload))
        await transport.setAfterUpload { await session.set(nil) }
        let coordinator = SubmissionCoordinator(store: store, session: session, transport: transport)
        try await coordinator.enqueue(draftID: id, context: context)
        let calls = await transport.calls
        XCTAssertTrue(calls.requests.isEmpty)
        let otherID = await store.completedRemoteID(for: id, ownerID: UUID())
        XCTAssertNil(otherID)
    }

    func testDependentSubmissionWaitsForSameOwnersCompletedParent() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let store = MemorySubmissionStore()
        let transport = FakeSubmissionTransport()
        let parentID = UUID()
        let childID = UUID()
        let payload = SubmissionPayload.rakugaki(.init(targetPhotoID: nil,
            mimeType: "image/png", byteSize: 4, sha256: String(repeating: "a", count: 64)))
        let child = PendingSubmission(id: childID, ownerID: owner, schemaVersion: 1,
            kind: .rakugaki, payloadData: try JSONEncoder().encode(payload),
            localFilePaths: ["draft.png"],
            assetPaths: [AssetReference(bucket: "rakugakis", path: "\(owner)/rakugakis/\(childID).png")!],
            dependsOn: parentID, remoteID: nil, state: .queued, resumeStage: .upload,
            attemptCount: 0, nextAttemptAt: nil, lastFailure: nil, leaseOwner: nil,
            leaseExpiresAt: nil, createdAt: Date(), updatedAt: Date())!
        try await store.insertDraft(child)
        let coordinator = SubmissionCoordinator(store: store,
                                                session: FakeSubmissionSession(context: context),
                                                transport: transport)
        await coordinator.resume(context: context)
        var calls = await transport.calls
        XCTAssertEqual(calls.uploads, 0)
        let parent = try makeDraft(id: parentID, owner: owner, payload: photoPayload())
        let completed = parent.replacingProgress(state: .completed, resumeStage: .none,
            remoteID: UUID(), attemptCount: 1, nextAttemptAt: nil, lastFailure: nil,
            leaseOwner: nil, leaseExpiresAt: nil, updatedAt: Date())!
        try await store.insertDraft(completed)
        await coordinator.resume(context: context)
        calls = await transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [childID])
    }

    func testLegacyGroupAnswerIsRetainedForCorrectionWithoutRPC() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let store = MemorySubmissionStore()
        let transport = FakeSubmissionTransport()
        let id = UUID()
        let payload = SubmissionPayload.groupAnswer(.init(missionID: UUID(),
                                                            targetPhotoID: UUID()))
        let legacy = PendingSubmission(id: id, ownerID: owner, schemaVersion: 1,
            kind: .groupAnswer, payloadData: try JSONEncoder().encode(payload),
            localFilePaths: [], assetPaths: [], dependsOn: nil, remoteID: nil,
            state: .outcomeUnknown, resumeStage: .register, attemptCount: 1,
            nextAttemptAt: Date(), lastFailure: .outcomeUnknown,
            leaseOwner: nil, leaseExpiresAt: nil,
            createdAt: Date().addingTimeInterval(-10), updatedAt: Date())!
        try await store.insertDraft(legacy)
        let coordinator = SubmissionCoordinator(store: store,
            session: FakeSubmissionSession(context: context), transport: transport)
        await coordinator.resume(context: context)
        let rows = await store.listPending(ownerID: owner)
        XCTAssertEqual(rows.first?.state, .needsCorrection)
        XCTAssertEqual(rows.first?.id, id)
        let calls = await transport.calls
        XCTAssertTrue(calls.requests.isEmpty)
    }

    private func makeDraft(id: UUID, owner: UUID, payload: SubmissionPayload) throws -> PendingSubmission {
        let data = try JSONEncoder().encode(payload)
        return PendingSubmission(id: id, ownerID: owner, schemaVersion: 1, kind: .photo,
                                 payloadData: data, localFilePaths: ["draft.jpg"],
                                 assetPaths: [AssetReference(bucket: "photos", path: "\(owner)/photos/\(id).jpg")!],
                                 dependsOn: nil, remoteID: nil, state: .draft, resumeStage: .upload,
                                 attemptCount: 0, nextAttemptAt: nil, lastFailure: nil,
                                 leaseOwner: nil, leaseExpiresAt: nil, createdAt: Date(), updatedAt: Date())!
    }

    private func photoPayload() -> SubmissionPayload {
        .photo(.init(title: "写真", point: GeoPoint(latitude: 35, longitude: 139)!,
                     privacy: .anyone, drawPermission: .anyone, requiresApproval: false,
                     mimeType: "image/jpeg", byteSize: 4,
                     sha256: String(repeating: "a", count: 64)))
    }
}

private actor FakeSubmissionSession: SessionProviding {
    var context: SessionContext?
    init(context: SessionContext) { self.context = context }
    func set(_ context: SessionContext?) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}

private actor FakeSubmissionTransport: SubmissionTransport {
    var uploads = 0
    var requests: [UUID] = []
    var loseFirstResponse = false
    var afterUpload: (@Sendable () async -> Void)?
    var uploadDelay: Duration = .zero
    var calls: (uploads: Int, requests: [UUID]) { (uploads, requests) }
    func setLoseFirstResponse() { loseFirstResponse = true }
    func setAfterUpload(_ action: @escaping @Sendable () async -> Void) { afterUpload = action }
    func setUploadDelay(_ value: Duration) { uploadDelay = value }
    func ensureUploaded(_ submission: PendingSubmission, payload: SubmissionPayload, context: SessionContext) async throws {
        uploads += 1
        try await Task.sleep(for: uploadDelay)
        await afterUpload?()
    }
    func register(_ submission: PendingSubmission, payload: SubmissionPayload,
                  dependencyRemoteID: UUID?, relatedPhotoRemoteID: UUID?,
                  context: SessionContext) async throws -> UUID {
        requests.append(submission.id)
        if loseFirstResponse { loseFirstResponse = false; throw AppFailure.outcomeUnknown }
        return submission.id
    }
}

private actor MemorySubmissionStore: SubmissionStoring {
    var rows: [UUID: PendingSubmission] = [:]
    var failCompletion = false
    func failNextCompletionSave() { failCompletion = true }
    func insertDraft(_ submission: PendingSubmission) throws { rows[submission.id] = submission }
    func listPending(ownerID: UUID) -> [PendingSubmission] { rows.values.filter { $0.ownerID == ownerID && $0.state != .completed && $0.state != .cancelled } }
    func completedRemoteID(for dependencyID: UUID, ownerID: UUID) -> UUID? {
        guard let row = rows[dependencyID], row.ownerID == ownerID, row.state == .completed else { return nil }
        return row.remoteID
    }
    func claim(id: UUID, ownerID: UUID, leaseOwner: UUID, leaseExpiresAt: Date) -> PendingSubmission? {
        guard let row = rows[id], row.ownerID == ownerID, row.leaseOwner == nil else { return nil }
        let claimed = row.replacingProgress(state: row.state, resumeStage: row.resumeStage, remoteID: row.remoteID,
            attemptCount: row.attemptCount, nextAttemptAt: row.nextAttemptAt, lastFailure: row.lastFailure,
            leaseOwner: leaseOwner, leaseExpiresAt: leaseExpiresAt, updatedAt: Date())!
        rows[id] = claimed
        return claimed
    }
    func save(_ submission: PendingSubmission, leaseOwner: UUID) throws {
        if submission.state == .completed && failCompletion {
            failCompletion = false
            throw AppFailure.serviceUnavailable
        }
        rows[submission.id] = submission
    }
    func release(id: UUID, ownerID: UUID, leaseOwner: UUID) throws {
        guard let row = rows[id], row.ownerID == ownerID, row.leaseOwner == leaseOwner else { return }
        rows[id] = row.replacingProgress(state: row.state, resumeStage: row.resumeStage, remoteID: row.remoteID,
            attemptCount: row.attemptCount, nextAttemptAt: row.nextAttemptAt, lastFailure: row.lastFailure,
            leaseOwner: nil, leaseExpiresAt: nil, updatedAt: Date())!
    }
}
