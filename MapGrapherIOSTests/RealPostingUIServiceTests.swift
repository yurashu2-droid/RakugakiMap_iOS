import Foundation
import MapGrapherCore
import XCTest
@testable import MapGrapherIOS

@MainActor
final class RealPostingUIServiceTests: XCTestCase {
    func testSaveTwiceKeepsOneFrozenOperationAndSubmitCompletes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft()
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        try await fixture.service.saveDraft(draft)
        let before = try await fixture.store.listPending(ownerID: fixture.context.userID)
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(before[0].id, draft.id)
        XCTAssertTrue(before[0].assetPaths[0].path.hasPrefix(
            fixture.context.userID.uuidString.lowercased() + "/photos/"))
        let savedPath = try XCTUnwrap(before[0].localFilePaths.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPath))
        let result = try await fixture.service.submit(draft)
        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.remotePhotoID, draft.id)
        try await fixture.service.saveDraft(draft)
        let repeated = try await fixture.service.submit(draft)
        XCTAssertEqual(repeated.remotePhotoID, draft.id)
        let calls = await fixture.transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [draft.id])
        XCTAssertFalse(fixture.service.storesDraftsPersistently)
    }

    func testLostResponseRetriesSameIDWithoutSecondUpload() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.transport.setLoseFirstResponse()
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft()
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        let waiting = try await fixture.service.submit(draft)
        XCTAssertEqual(waiting.state, .outcomeUnknown)
        try await fixture.service.saveDraft(draft)
        let completed = try await fixture.service.submit(draft)
        XCTAssertEqual(completed.state, .completed)
        let calls = await fixture.transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [draft.id, draft.id])
    }

    func testChangedAccountCannotSubmitOtherOwnersDraft() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft()
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        await fixture.session.set(SessionContext(userID: UUID(), epoch: UUID()))
        do {
            _ = try await fixture.service.submit(draft)
            XCTFail("別アカウントの下書きは投稿できません")
        } catch { }
        let calls = await fixture.transport.calls
        XCTAssertTrue(calls.requests.isEmpty)
    }

    func testPreparedImageCannotBeSavedAfterAccountSwitch() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft()
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        let switched = SessionContext(userID: UUID(), epoch: UUID())
        await fixture.session.set(switched)
        do {
            try await fixture.service.saveDraft(draft)
            XCTFail("Aで準備した画像をBの投稿として保存できません")
        } catch let error as PostingServiceError {
            XCTAssertEqual(error, .permissionDenied)
        }
        let ownerRows = try await fixture.store.listPending(ownerID: fixture.context.userID)
        let switchedRows = try await fixture.store.listPending(ownerID: switched.userID)
        XCTAssertTrue(ownerRows.isEmpty)
        XCTAssertTrue(switchedRows.isEmpty)
    }

    func testARReservationFailsExplicitly() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft()
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        draft.reserveAR = true
        do {
            try await fixture.service.saveDraft(draft)
            XCTFail("AR予約を黙って成功させてはいけません")
        } catch let error as PostingServiceError {
            XCTAssertEqual(error, .invalidDraft)
        }
        let rows = try await fixture.store.listPending(ownerID: fixture.context.userID)
        XCTAssertTrue(rows.isEmpty)
    }

    func testMissionAnswerWaitsForPhotoAndCompletesAsDependentOperation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft(missionID: UUID())
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        let before = try await fixture.store.listPending(ownerID: fixture.context.userID)
        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(before.first(where: { $0.kind == .groupAnswer })?.dependsOn, draft.id)
        let result = try await fixture.service.submit(draft)
        XCTAssertEqual(result.state, .completed)
        let calls = await fixture.transport.calls
        XCTAssertEqual(calls.requests.count, 2)
        XCTAssertEqual(calls.requests.first, draft.id)
    }

    private func makeFixture() throws -> ServiceFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("real-posting-test-\(UUID().uuidString)")
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let session = PostingTestSession(context)
        let store = PostingTestStore()
        let transport = PostingTestTransport()
        let coordinator = SubmissionCoordinator(store: store, session: session,
                                                transport: transport)
        let files = try DraftFileStore(rootURL: root.appendingPathComponent("Drafts"))
        let service = RealPostingUIService(
            context: context, session: session, store: store, coordinator: coordinator, files: files,
            imagePreparer: ImagePreparer(outputDirectory: root.appendingPathComponent("Prepared")),
            drawingExporter: DrawingExporter(outputDirectory: root.appendingPathComponent("Drawing")),
            location: PostingTestLocation())
        return ServiceFixture(root: root, context: context, service: service,
                              session: session, store: store, transport: transport)
    }
}

@MainActor
private struct ServiceFixture {
    let root: URL
    let context: SessionContext
    let service: RealPostingUIService
    let session: PostingTestSession
    let store: PostingTestStore
    let transport: PostingTestTransport
}

@MainActor
private struct PostingTestLocation: MapLocationProviding {
    func requestCurrentLocation() async -> MapLocationState {
        .ready(GeoPoint(latitude: 35, longitude: 139)!)
    }
}

private actor PostingTestSession: SessionProviding {
    var context: SessionContext?
    init(_ context: SessionContext) { self.context = context }
    func set(_ context: SessionContext?) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}

private actor PostingTestTransport: SubmissionTransport {
    var uploads = 0
    var requests: [UUID] = []
    var loseFirstResponse = false
    var calls: (uploads: Int, requests: [UUID]) { (uploads, requests) }
    func setLoseFirstResponse() { loseFirstResponse = true }
    func ensureUploaded(_ submission: PendingSubmission, payload: SubmissionPayload,
                        context: SessionContext) async throws { uploads += 1 }
    func register(_ submission: PendingSubmission, payload: SubmissionPayload,
                  dependencyRemoteID: UUID?, relatedPhotoRemoteID: UUID?,
                  context: SessionContext) async throws -> UUID {
        requests.append(submission.id)
        if loseFirstResponse { loseFirstResponse = false; throw AppFailure.outcomeUnknown }
        return submission.id
    }
}

private actor PostingTestStore: SubmissionStoring {
    var rows: [UUID: PendingSubmission] = [:]
    func insertDraft(_ row: PendingSubmission) throws { rows[row.id] = row }
    func listPending(ownerID: UUID) -> [PendingSubmission] {
        rows.values.filter { $0.ownerID == ownerID && $0.state != .completed && $0.state != .cancelled }
    }
    func completedRemoteID(for dependencyID: UUID, ownerID: UUID) -> UUID? {
        guard let row = rows[dependencyID], row.ownerID == ownerID, row.state == .completed else { return nil }
        return row.remoteID
    }
    func claim(id: UUID, ownerID: UUID, leaseOwner: UUID,
               leaseExpiresAt: Date) -> PendingSubmission? {
        guard let row = rows[id], row.ownerID == ownerID, row.leaseOwner == nil else { return nil }
        let claimed = row.replacingProgress(state: row.state, resumeStage: row.resumeStage,
            remoteID: row.remoteID, attemptCount: row.attemptCount, nextAttemptAt: row.nextAttemptAt,
            lastFailure: row.lastFailure, leaseOwner: leaseOwner, leaseExpiresAt: leaseExpiresAt,
            updatedAt: max(Date(), row.updatedAt))!
        rows[id] = claimed
        return claimed
    }
    func save(_ row: PendingSubmission, leaseOwner: UUID) throws { rows[row.id] = row }
    func release(id: UUID, ownerID: UUID, leaseOwner: UUID) throws {
        guard let row = rows[id], row.ownerID == ownerID, row.leaseOwner == leaseOwner else { return }
        rows[id] = row.replacingProgress(state: row.state, resumeStage: row.resumeStage,
            remoteID: row.remoteID, attemptCount: row.attemptCount, nextAttemptAt: row.nextAttemptAt,
            lastFailure: row.lastFailure, leaseOwner: nil, leaseExpiresAt: nil,
            updatedAt: max(Date(), row.updatedAt))!
    }
}
