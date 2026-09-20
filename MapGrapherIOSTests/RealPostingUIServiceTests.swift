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

    func testARReservationRequiresDrawing() async throws {
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
            XCTFail("ラクガキなしのAR投稿は保存できません")
        } catch let error as PostingServiceError {
            XCTAssertEqual(error, .invalidDraft)
        }
        let rows = try await fixture.store.listPending(ownerID: fixture.context.userID)
        XCTAssertTrue(rows.isEmpty)
    }

    func testOneTapARPostRegistersPhotoDrawingAndExperienceInOrder() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft()
        draft.preparedImage = prepared
        draft.title = "AR写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        draft.drawing = sampleDrawing(width: prepared.prepared.pixelWidth,
                                      height: prepared.prepared.pixelHeight)
        draft.reserveAR = true

        try await fixture.service.saveDraft(draft)
        let rows = try await fixture.store.listPending(ownerID: fixture.context.userID)
        XCTAssertEqual(Set(rows.map(\.kind)), Set([.photo, .rakugaki, .ar]))
        let drawing = try XCTUnwrap(rows.first { $0.kind == .rakugaki })
        let ar = try XCTUnwrap(rows.first { $0.kind == .ar })
        XCTAssertEqual(drawing.dependsOn, draft.id)
        XCTAssertEqual(ar.dependsOn, drawing.id)
        XCTAssertEqual(drawing.state, .queued)
        XCTAssertEqual(ar.state, .queued)
        let payload = try JSONDecoder().decode(SubmissionPayload.self, from: ar.payloadData)
        guard case let .ar(settings) = payload else { return XCTFail("AR設定が必要です") }
        XCTAssertEqual(settings.targetPhotoOperationID, draft.id)
        XCTAssertEqual(settings.unlockRadiusM, 50)
        XCTAssertEqual(settings.discoveryRadiusM, 150)
        XCTAssertEqual(settings.displayWidthM, 1)

        let result = try await fixture.service.submit(draft)
        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.remotePhotoID, draft.id)
        let calls = await fixture.transport.calls
        XCTAssertEqual(calls.requests, [draft.id, drawing.id, ar.id])
    }

    private func sampleDrawing(width: Int, height: Int) -> DrawingDocument {
        let stroke = DrawingStroke(id: UUID(), brush: .pen,
            color: DrawingColor(red: 1, green: 0, blue: 0, alpha: 1)!,
            width: 4, opacity: 1,
            points: [DrawingPoint(x: 16, y: 16)!], randomSeed: 123)!
        return DrawingDocument(pixelWidth: width, pixelHeight: height, strokes: [stroke])!
    }

    func testMissionAnswerWaitsForPhotoAndCompletesThroughJournal() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft(missionID: UUID())
        fixture.missionRemote.missionID = draft.missionID
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        let before = try await fixture.store.listPending(ownerID: fixture.context.userID)
        XCTAssertEqual(before.count, 1)
        XCTAssertFalse(before.contains(where: { $0.kind == .groupAnswer }))
        let result = try await fixture.service.submit(draft)
        XCTAssertEqual(result.state, .completed)
        let calls = await fixture.transport.calls
        XCTAssertEqual(calls.requests, [draft.id])
        XCTAssertEqual(fixture.missionRemote.submitCount, 1)
        let answerRows = try await fixture.answerJournal.list(ownerID: fixture.context.userID)
        XCTAssertEqual(answerRows.first?.remotePhotoID, draft.id)
        XCTAssertEqual(answerRows.first?.phase, .completed)
    }

    func testMissionAnswerDoesNotSendBeforePhotoCompletes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.transport.setLoseFirstResponse()
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft(missionID: UUID())
        fixture.missionRemote.missionID = draft.missionID
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        let first = try await fixture.service.submit(draft)
        XCTAssertEqual(first.state, .outcomeUnknown)
        XCTAssertEqual(fixture.missionRemote.submitCount, 0)
        let second = try await fixture.service.submit(draft)
        XCTAssertEqual(second.state, .completed)
        XCTAssertEqual(fixture.missionRemote.submitCount, 1)
    }

    func testMissionDayChangeRetainsPhotoWithoutAnswerRPC() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft(missionID: UUID())
        fixture.missionRemote.missionID = draft.missionID
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        fixture.missionRemote.missionDate = "2026-09-22"
        let result = try await fixture.service.submit(draft)
        XCTAssertEqual(result.state, .needsCorrection)
        XCTAssertEqual(result.remotePhotoID, draft.id)
        XCTAssertEqual(fixture.missionRemote.submitCount, 0)
        let rows = try await fixture.answerJournal.list(ownerID: fixture.context.userID)
        XCTAssertEqual(rows.first?.missionDate, "2026-09-21")
        XCTAssertEqual(rows.first?.remotePhotoID, draft.id)
    }

    func testMissionResponseLossDoesNotReplayAnswer() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = try await fixture.service.prepareImage(
            data: FakePostingUIService.fixtureImageData(), suggestedFilename: "camera.png")
        var draft = PostingDraft(missionID: UUID())
        fixture.missionRemote.missionID = draft.missionID
        fixture.missionRemote.loseResponse = true
        draft.preparedImage = prepared
        draft.title = "写真"
        draft.location = GeoPoint(latitude: 35, longitude: 139)
        try await fixture.service.saveDraft(draft)
        let first = try await fixture.service.submit(draft)
        XCTAssertEqual(first.state, .needsCorrection)
        XCTAssertEqual(first.remotePhotoID, draft.id)
        let second = try await fixture.service.submit(draft)
        XCTAssertEqual(second.state, .needsCorrection)
        XCTAssertEqual(fixture.missionRemote.submitCount, 1)
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
        let groupID = UUID()
        let missionRemote = PostingMissionRemote(groupID: groupID, ownerID: owner)
        let answerJournal = try GroupAnswerRecoveryStore(
            rootURL: root.appendingPathComponent("GroupAnswers"))
        let answerRecovery = GroupAnswerRecovery(journal: answerJournal,
            photos: SubmissionPhotoLookup(submissions: store),
            remote: missionRemote, session: session)
        let service = RealPostingUIService(
            context: context, session: session, store: store, coordinator: coordinator, files: files,
            imagePreparer: ImagePreparer(outputDirectory: root.appendingPathComponent("Prepared")),
            drawingExporter: DrawingExporter(outputDirectory: root.appendingPathComponent("Drawing")),
            location: PostingTestLocation(),
            missionLookup: PostingMissionLookup(groupID: groupID),
            answerRecovery: answerRecovery)
        return ServiceFixture(root: root, context: context, service: service,
                              session: session, store: store, transport: transport,
                              missionRemote: missionRemote, answerJournal: answerJournal)
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
    let missionRemote: PostingMissionRemote
    let answerJournal: GroupAnswerRecoveryStore
}

@MainActor
private struct PostingMissionLookup: GroupMissionSnapshotLookingUp {
    let groupID: UUID
    func current(missionID: UUID, context: SessionContext) async throws -> GroupMissionSnapshot? {
        GroupMissionSnapshot(groupID: groupID, missionID: missionID,
                             missionDate: "2026-09-21")
    }
}

@MainActor
private final class PostingMissionRemote: MissionAnswerRemote {
    let groupID: UUID
    let ownerID: UUID
    var missionID: UUID?
    var missionDate = "2026-09-21"
    var submitCount = 0
    var loseResponse = false
    init(groupID: UUID, ownerID: UUID) {
        self.groupID = groupID; self.ownerID = ownerID
    }
    func missionStatus(groupID: UUID, context: SessionContext) async throws -> [GroupMissionParticipant] {
        guard let missionID else { return [] }
        return [GroupMissionParticipant(missionID: missionID, groupID: groupID,
            missionDate: missionDate, missionStatus: .open,
            promptText: "お題", setterID: nil, participantID: ownerID,
            participantName: "本人", participantAvatar: nil,
            rotationOrderSnapshot: 0, isActive: true, answered: false,
            answerID: nil, answerPhotoID: nil, answerCreatedAt: nil,
            photoAsset: nil, latestApprovedRakugakiAsset: nil)]
    }
    func submitAnswer(missionID: UUID, photoID: UUID,
                      context: SessionContext) async throws -> GroupAnswer {
        submitCount += 1
        if loseResponse { throw URLError(.networkConnectionLost) }
        return GroupAnswer(id: UUID(), missionID: missionID, userID: ownerID,
            photoID: photoID, createdAt: Date(), updatedAt: Date())
    }
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
