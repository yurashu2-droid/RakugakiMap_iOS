import Foundation
import MapGrapherCore
import UIKit
import XCTest
@testable import MapGrapherIOS

@MainActor
final class ExistingPhotoRakugakiServiceTests: XCTestCase {
    func testPrepareRequiresDrawPermissionBeforePrivateDownload() async throws {
        let fixture = try RakugakiFixture(canDraw: false)
        defer { fixture.remove() }
        do {
            _ = try await fixture.service.prepare(photo: fixture.photo)
            XCTFail("描画権限がない写真を開いてはいけません")
        } catch let failure as AppFailure {
            XCTAssertEqual(failure, .forbidden)
        }
        XCTAssertEqual(fixture.imageLoader.calls, 0)
    }

    func testExistingPhotoDrawingUploadsTransparentPNGAndReportsPending() async throws {
        let fixture = try RakugakiFixture()
        defer { fixture.remove() }
        let base = try await fixture.service.prepare(photo: fixture.photo)
        defer { fixture.service.discard(base: base) }
        let operationID = UUID()
        let result = try await fixture.service.submit(photo: fixture.photo, base: base,
            document: fixture.document(), operationID: operationID)
        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.approval, .pending)
        XCTAssertEqual(result.remoteRakugakiID, operationID)
        let calls = await fixture.transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [operationID])
        XCTAssertEqual(calls.targetPhotoIDs, [fixture.photo.id])
        let remotePath = try XCTUnwrap(calls.assetPaths.first)
        XCTAssertTrue(remotePath.hasPrefix(fixture.context.userID.uuidString.lowercased()))
        XCTAssertTrue(remotePath.hasSuffix(".png"))
        let local = try XCTUnwrap(calls.localFiles.first)
        let data = try Data(contentsOf: URL(fileURLWithPath: local))
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }

    func testLostRegistrationResponseUsesSameRequestIDAndUpload() async throws {
        let fixture = try RakugakiFixture()
        defer { fixture.remove() }
        await fixture.transport.loseFirstResponse()
        let base = try await fixture.service.prepare(photo: fixture.photo)
        defer { fixture.service.discard(base: base) }
        let operationID = UUID()
        let document = fixture.document()
        let first = try await fixture.service.submit(photo: fixture.photo, base: base,
            document: document, operationID: operationID)
        XCTAssertEqual(first.state, .outcomeUnknown)
        let second = try await fixture.service.submit(photo: fixture.photo, base: base,
            document: document, operationID: operationID)
        XCTAssertEqual(second.state, .completed)
        let calls = await fixture.transport.calls
        XCTAssertEqual(calls.uploads, 1)
        XCTAssertEqual(calls.requests, [operationID, operationID])
    }

    func testSessionSwitchRejectsPreparedPrivatePhoto() async throws {
        let fixture = try RakugakiFixture()
        defer { fixture.remove() }
        let base = try await fixture.service.prepare(photo: fixture.photo)
        defer { fixture.service.discard(base: base) }
        await fixture.session.set(SessionContext(userID: UUID(), epoch: UUID()))
        do {
            _ = try await fixture.service.submit(photo: fixture.photo, base: base,
                document: fixture.document(), operationID: UUID())
            XCTFail("旧sessionの基底画像を使用してはいけません")
        } catch let failure as AppFailure {
            XCTAssertEqual(failure, .cancelled)
        }
        let calls = await fixture.transport.calls
        XCTAssertTrue(calls.requests.isEmpty)
    }

    func testCompletedReceiptWithoutVisibleRowDoesNotClaimApproval() async throws {
        let fixture = try RakugakiFixture()
        defer { fixture.remove() }
        fixture.approvalReader.value = nil
        let base = try await fixture.service.prepare(photo: fixture.photo)
        defer { fixture.service.discard(base: base) }
        let result = try await fixture.service.submit(photo: fixture.photo, base: base,
            document: fixture.document(), operationID: UUID())
        XCTAssertEqual(result.state, .needsCorrection)
        XCTAssertNil(result.approval)
        XCTAssertNotNil(result.remoteRakugakiID)
    }
}

@MainActor
private final class RakugakiFixture {
    let root: URL
    let context: SessionContext
    let photo: Photo
    let session: RakugakiTestSession
    let imageLoader: RakugakiTestImageLoader
    let transport: RakugakiTestTransport
    let approvalReader: RakugakiTestApprovalReader
    let service: ExistingPhotoRakugakiService

    init(canDraw: Bool = true) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("existing-rakugaki-test-\(UUID().uuidString)")
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let photo = Photo(id: UUID(), ownerID: UUID(), title: "既存写真",
            location: GeoPoint(latitude: 35, longitude: 139)!,
            visibility: .anyone, drawPermission: .anyone,
            requiresApproval: true, createdAt: Date(),
            asset: AssetReference(bucket: "photos", path: "private/test.jpg")!,
            thumbnail: nil, likeCount: 0, likedByMe: false)!
        let session = RakugakiTestSession(context)
        let imageLoader = RakugakiTestImageLoader()
        let transport = RakugakiTestTransport()
        let approvalReader = RakugakiTestApprovalReader()
        let store = RakugakiTestStore()
        let coordinator = SubmissionCoordinator(store: store, session: session,
                                                transport: transport)
        let service = ExistingPhotoRakugakiService(context: context, session: session,
            permissions: RakugakiTestPermissions(canDraw: canDraw),
            imageLoader: imageLoader, store: store, coordinator: coordinator,
            files: try DraftFileStore(rootURL: root.appendingPathComponent("Drafts")),
            exporter: DrawingExporter(outputDirectory: root.appendingPathComponent("Export")),
            approvalReader: approvalReader)
        self.root = root; self.context = context; self.photo = photo
        self.session = session; self.imageLoader = imageLoader
        self.transport = transport; self.approvalReader = approvalReader
        self.service = service
    }

    func document() -> DrawingDocument {
        let point = DrawingPoint(x: 16, y: 16)!
        let stroke = DrawingStroke(id: UUID(), brush: .pen,
            color: DrawingColor(red: 1, green: 0, blue: 0, alpha: 1)!,
            width: 4, opacity: 1, points: [point], randomSeed: 123)!
        return DrawingDocument(pixelWidth: 32, pixelHeight: 32, strokes: [stroke])!
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private struct RakugakiTestPermissions: PhotoReading {
    let canDraw: Bool
    func nearby(center: GeoPoint, radiusM: Double) async throws -> [Photo] { [] }
    func permissions(photoID: UUID) async throws -> PhotoPermissions {
        PhotoPermissions(canView: true, canDraw: canDraw, isOwner: false)
    }
}

@MainActor
private final class RakugakiTestImageLoader: RakugakiBaseImageLoading {
    var calls = 0
    func load(asset: AssetReference, context: SessionContext) async throws -> UIImage {
        calls += 1
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32),
                                       format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }
}

@MainActor
private final class RakugakiTestApprovalReader: RakugakiApprovalReading {
    var value: ApprovalStatus? = .pending
    func status(rakugakiID: UUID, photoID: UUID,
                context: SessionContext) async throws -> ApprovalStatus? { value }
}

private actor RakugakiTestSession: SessionProviding {
    var context: SessionContext?
    init(_ context: SessionContext) { self.context = context }
    func set(_ context: SessionContext?) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}

private actor RakugakiTestTransport: SubmissionTransport {
    var uploads = 0
    var requests: [UUID] = []
    var targetPhotoIDs: [UUID] = []
    var assetPaths: [String] = []
    var localFiles: [String] = []
    var shouldLoseFirstResponse = false
    var calls: (uploads: Int, requests: [UUID], targetPhotoIDs: [UUID],
                assetPaths: [String], localFiles: [String]) {
        (uploads, requests, targetPhotoIDs, assetPaths, localFiles)
    }
    func loseFirstResponse() { shouldLoseFirstResponse = true }
    func ensureUploaded(_ submission: PendingSubmission, payload: SubmissionPayload,
                        context: SessionContext) async throws {
        uploads += 1
        assetPaths.append(submission.assetPaths[0].path)
        localFiles.append(submission.localFilePaths[0])
    }
    func register(_ submission: PendingSubmission, payload: SubmissionPayload,
                  dependencyRemoteID: UUID?, relatedPhotoRemoteID: UUID?,
                  context: SessionContext) async throws -> UUID {
        requests.append(submission.id)
        if case .rakugaki(let value) = payload, let id = value.targetPhotoID {
            targetPhotoIDs.append(id)
        }
        if shouldLoseFirstResponse {
            shouldLoseFirstResponse = false
            throw AppFailure.outcomeUnknown
        }
        return submission.id
    }
}

private actor RakugakiTestStore: SubmissionStoring {
    var rows: [UUID: PendingSubmission] = [:]
    func insertDraft(_ row: PendingSubmission) throws { rows[row.id] = row }
    func listPending(ownerID: UUID) -> [PendingSubmission] {
        rows.values.filter { $0.ownerID == ownerID && $0.state != .completed && $0.state != .cancelled }
    }
    func completedRemoteID(for dependencyID: UUID, ownerID: UUID) -> UUID? {
        guard let row = rows[dependencyID], row.ownerID == ownerID,
              row.state == .completed else { return nil }
        return row.remoteID
    }
    func claim(id: UUID, ownerID: UUID, leaseOwner: UUID,
               leaseExpiresAt: Date) -> PendingSubmission? {
        guard let row = rows[id], row.ownerID == ownerID, row.leaseOwner == nil else { return nil }
        let claimed = row.replacingProgress(state: row.state, resumeStage: row.resumeStage,
            remoteID: row.remoteID, attemptCount: row.attemptCount,
            nextAttemptAt: row.nextAttemptAt, lastFailure: row.lastFailure,
            leaseOwner: leaseOwner, leaseExpiresAt: leaseExpiresAt,
            updatedAt: max(Date(), row.updatedAt))!
        rows[id] = claimed
        return claimed
    }
    func save(_ row: PendingSubmission, leaseOwner: UUID) throws { rows[row.id] = row }
    func release(id: UUID, ownerID: UUID, leaseOwner: UUID) throws {
        guard let row = rows[id], row.ownerID == ownerID,
              row.leaseOwner == leaseOwner else { return }
        rows[id] = row.replacingProgress(state: row.state, resumeStage: row.resumeStage,
            remoteID: row.remoteID, attemptCount: row.attemptCount,
            nextAttemptAt: row.nextAttemptAt, lastFailure: row.lastFailure,
            leaseOwner: nil, leaseExpiresAt: nil,
            updatedAt: max(Date(), row.updatedAt))!
    }
}
