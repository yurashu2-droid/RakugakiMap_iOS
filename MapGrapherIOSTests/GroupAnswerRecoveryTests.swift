import Foundation
import MapGrapherCore
import XCTest
@testable import MapGrapherIOS

@MainActor
final class GroupAnswerRecoveryTests: XCTestCase {
    func testPhotoIDPersistsAndCompletedAnswerCanBeRestored() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let photoOperationID = UUID()
        let remotePhotoID = UUID()
        let remoteAnswerID = UUID()
        let created = try await fixture.recovery.create(
            operationID: operationID, groupID: fixture.groupID,
            missionID: fixture.missionID, missionDate: fixture.missionDate,
            photoOperationID: photoOperationID, context: fixture.context)
        XCTAssertEqual(created.phase, .awaitingPhoto)

        let waiting = try await fixture.recovery.submit(operationID: operationID,
                                                        context: fixture.context)
        XCTAssertEqual(waiting.phase, .awaitingPhoto)
        XCTAssertEqual(fixture.remote.submitCount, 0)

        await fixture.photos.set(remotePhotoID, for: photoOperationID)
        fixture.remote.onSubmit = { missionID, photoID in
            GroupAnswer(id: remoteAnswerID, missionID: missionID,
                        userID: fixture.context.userID, photoID: photoID,
                        createdAt: Date(), updatedAt: Date())
        }
        let completed = try await fixture.recovery.submit(operationID: operationID,
                                                          context: fixture.context)
        XCTAssertEqual(completed.phase, .completed)
        XCTAssertEqual(completed.remotePhotoID, remotePhotoID)
        XCTAssertEqual(completed.remoteAnswerID, remoteAnswerID)
        XCTAssertEqual(fixture.remote.submitCount, 1)

        let reopened = try GroupAnswerRecoveryStore(rootURL: fixture.root)
        let restored = try await reopened.load(id: operationID,
                                               ownerID: fixture.context.userID)
        XCTAssertEqual(restored?.remotePhotoID, remotePhotoID)
        XCTAssertEqual(restored?.remoteAnswerID, remoteAnswerID)
        XCTAssertEqual(restored?.missionDate, fixture.missionDate)
    }

    func testResponseLossReconcilesWithoutSecondSubmit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let photoOperationID = UUID()
        let photoID = UUID()
        let answerID = UUID()
        _ = try await fixture.recovery.create(operationID: operationID,
            groupID: fixture.groupID, missionID: fixture.missionID,
            missionDate: fixture.missionDate, photoOperationID: photoOperationID,
            context: fixture.context)
        await fixture.photos.set(photoID, for: photoOperationID)
        fixture.remote.onSubmit = { _, _ in
            fixture.remote.rows = [fixture.participant(answerID: answerID,
                                                       answerPhotoID: photoID)]
            throw URLError(.networkConnectionLost)
        }
        let result = try await fixture.recovery.submit(operationID: operationID,
                                                       context: fixture.context)
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.remotePhotoID, photoID)
        XCTAssertEqual(result.remoteAnswerID, answerID)
        _ = try await fixture.recovery.submit(operationID: operationID,
                                              context: fixture.context)
        XCTAssertEqual(fixture.remote.submitCount, 1)
    }

    func testUnknownOutcomeNeedsCorrectionAndRetainsPhoto() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let photoOperationID = UUID()
        let photoID = UUID()
        _ = try await fixture.recovery.create(operationID: operationID,
            groupID: fixture.groupID, missionID: fixture.missionID,
            missionDate: fixture.missionDate, photoOperationID: photoOperationID,
            context: fixture.context)
        await fixture.photos.set(photoID, for: photoOperationID)
        fixture.remote.onSubmit = { _, _ in throw URLError(.networkConnectionLost) }
        let result = try await fixture.recovery.submit(operationID: operationID,
                                                       context: fixture.context)
        XCTAssertEqual(result.phase, .needsCorrection)
        XCTAssertEqual(result.remotePhotoID, photoID)
        _ = try await fixture.recovery.submit(operationID: operationID,
                                              context: fixture.context)
        XCTAssertEqual(fixture.remote.submitCount, 1)
    }

    func testJSTDayChangeNeverMovesAnswerToNewMission() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let photoOperationID = UUID()
        let photoID = UUID()
        _ = try await fixture.recovery.create(operationID: operationID,
            groupID: fixture.groupID, missionID: fixture.missionID,
            missionDate: fixture.missionDate, photoOperationID: photoOperationID,
            context: fixture.context)
        await fixture.photos.set(photoID, for: photoOperationID)
        fixture.remote.rows = [fixture.participant(missionID: UUID(),
                                                   missionDate: "2026-09-22")]
        let result = try await fixture.recovery.submit(operationID: operationID,
                                                       context: fixture.context)
        XCTAssertEqual(result.phase, .needsCorrection)
        XCTAssertEqual(result.missionID, fixture.missionID)
        XCTAssertEqual(result.missionDate, fixture.missionDate)
        XCTAssertEqual(result.remotePhotoID, photoID)
        XCTAssertEqual(fixture.remote.submitCount, 0)
    }

    func testAccountSwitchKeepsOldOwnerJournalAndRejectsOldResponse() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let photoOperationID = UUID()
        let photoID = UUID()
        _ = try await fixture.recovery.create(operationID: operationID,
            groupID: fixture.groupID, missionID: fixture.missionID,
            missionDate: fixture.missionDate, photoOperationID: photoOperationID,
            context: fixture.context)
        await fixture.photos.set(photoID, for: photoOperationID)
        let newContext = SessionContext(userID: UUID(), epoch: UUID())
        fixture.remote.onSubmit = { _, _ in
            await fixture.session.set(newContext)
            throw URLError(.networkConnectionLost)
        }
        do {
            _ = try await fixture.recovery.submit(operationID: operationID,
                                                  context: fixture.context)
            XCTFail("旧セッションの応答を採用してはいけません")
        } catch let failure as AppFailure {
            XCTAssertEqual(failure, .cancelled)
        }
        let oldRecord = try await fixture.journal.load(id: operationID,
                                                       ownerID: fixture.context.userID)
        XCTAssertEqual(oldRecord?.remotePhotoID, photoID)
        XCTAssertEqual(oldRecord?.phase, .outcomeUnknown)
        let newOwnerRows = try await fixture.recovery.list(context: newContext)
        XCTAssertTrue(newOwnerRows.isEmpty)
        XCTAssertEqual(fixture.remote.submitCount, 1)
    }

    func testRestartFromSubmittingOnlyReadsServer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let photoOperationID = UUID()
        let photoID = UUID()
        var operation = try await fixture.recovery.create(operationID: operationID,
            groupID: fixture.groupID, missionID: fixture.missionID,
            missionDate: fixture.missionDate, photoOperationID: photoOperationID,
            context: fixture.context)
        operation.remotePhotoID = photoID
        operation.phase = .submitting
        operation.updatedAt = Date()
        try await fixture.journal.save(operation)
        let recovered = try await fixture.recovery.submit(operationID: operationID,
                                                         context: fixture.context)
        XCTAssertEqual(recovered.phase, .needsCorrection)
        XCTAssertEqual(recovered.remotePhotoID, photoID)
        XCTAssertEqual(fixture.remote.submitCount, 0)
    }

    func testSameMissionRejectsSecondOperationID() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.recovery.create(operationID: UUID(),
            groupID: fixture.groupID, missionID: fixture.missionID,
            missionDate: fixture.missionDate, photoOperationID: UUID(),
            context: fixture.context)
        do {
            _ = try await fixture.recovery.create(operationID: UUID(),
                groupID: fixture.groupID, missionID: fixture.missionID,
                missionDate: fixture.missionDate, photoOperationID: UUID(),
                context: fixture.context)
            XCTFail("同じお題へ別操作IDから回答してはいけません")
        } catch let error as GroupAnswerStoreError {
            guard case .immutableInputChanged = error else { XCTFail("誤った失敗理由"); return }
        }
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let context = SessionContext(userID: UUID(), epoch: UUID())
    let groupID = UUID()
    let missionID = UUID()
    let missionDate = "2026-09-21"
    let journal: GroupAnswerRecoveryStore
    let photos = FakeCompletedPhotos()
    let remote = FakeMissionAnswerRemote()
    let session: FakeAnswerSession
    let recovery: GroupAnswerRecovery

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("group-answer-tests-\(UUID().uuidString)", isDirectory: true)
        journal = try GroupAnswerRecoveryStore(rootURL: root)
        session = FakeAnswerSession(context)
        recovery = GroupAnswerRecovery(journal: journal, photos: photos,
                                       remote: remote, session: session)
        remote.rows = [participant()]
    }

    func participant(missionID: UUID? = nil, missionDate: String? = nil,
                     answerID: UUID? = nil, answerPhotoID: UUID? = nil) -> GroupMissionParticipant {
        GroupMissionParticipant(missionID: missionID ?? self.missionID,
            groupID: groupID, missionDate: missionDate ?? self.missionDate,
            missionStatus: .open, promptText: "お題", setterID: nil,
            participantID: context.userID, participantName: "テスト",
            participantAvatar: nil, rotationOrderSnapshot: 0, isActive: true,
            answered: answerID != nil, answerID: answerID,
            answerPhotoID: answerPhotoID, answerCreatedAt: nil,
            photoAsset: nil, latestApprovedRakugakiAsset: nil)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor FakeCompletedPhotos: CompletedPhotoLookingUp {
    private var values: [UUID: UUID] = [:]
    func set(_ remoteID: UUID, for operationID: UUID) { values[operationID] = remoteID }
    func remoteID(for operationID: UUID, ownerID: UUID) async throws -> UUID? {
        values[operationID]
    }
}

private actor FakeAnswerSession: SessionProviding {
    private var context: SessionContext?
    init(_ context: SessionContext) { self.context = context }
    func set(_ context: SessionContext?) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}

@MainActor
private final class FakeMissionAnswerRemote: MissionAnswerRemote {
    var rows: [GroupMissionParticipant] = []
    var submitCount = 0
    var onSubmit: (@MainActor (UUID, UUID) async throws -> GroupAnswer)?

    func missionStatus(groupID: UUID,
                       context: SessionContext) async throws -> [GroupMissionParticipant] {
        rows
    }

    func submitAnswer(missionID: UUID, photoID: UUID,
                      context: SessionContext) async throws -> GroupAnswer {
        submitCount += 1
        if let onSubmit { return try await onSubmit(missionID, photoID) }
        return GroupAnswer(id: UUID(), missionID: missionID, userID: context.userID,
                           photoID: photoID, createdAt: Date(), updatedAt: Date())
    }
}
