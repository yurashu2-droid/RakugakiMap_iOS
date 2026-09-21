import Foundation
import MapGrapherCore
import XCTest
@testable import MapGrapherIOS

@MainActor
final class ARWorldMapStoreTests: XCTestCase {
    func testWorldMapExperienceRequiresCompleteMetadata() throws {
        let row = ArExperienceDTO(
            id: UUID(), photoId: UUID(), rakugakiId: UUID(),
            anchorType: .worldMapV1,
            assetPath: "owner/rakugakis/drawing.png",
            unlockRadiusM: 50, discoveryRadiusM: 150, displayWidthM: 1,
            latitude: 35, longitude: 139,
            worldMapPath: nil,
            anchorName: "rakugaki:00000000-0000-0000-0000-000000000001",
            fallbackAltitudeM: nil, fallbackHeadingDeg: nil,
            worldMapFormatVersion: 1)

        XCTAssertThrowsError(try ARRepository.mapForTesting(row))
    }

    func testLocalPlaneRemainsValidWithoutWorldMapMetadata() throws {
        let row = ArExperienceDTO(
            id: UUID(), photoId: UUID(), rakugakiId: UUID(),
            anchorType: .localPlane,
            assetPath: "owner/rakugakis/drawing.png",
            unlockRadiusM: 50, discoveryRadiusM: 150, displayWidthM: 1,
            latitude: 35, longitude: 139,
            worldMapPath: nil, anchorName: nil,
            fallbackAltitudeM: nil, fallbackHeadingDeg: nil,
            worldMapFormatVersion: nil)

        let result = try ARRepository.mapForTesting(row)
        XCTAssertNil(result.worldMap)
        XCTAssertNil(result.anchorName)
    }

    func testRpcFailureDeletesOnlyNewlyUploadedWorldMap() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = PersistentARTestSession(context)
        let store = PersistentARTestStore()
        let remote = PersistentARTestRemote()
        let photoID = UUID()
        let rakugakiID = UUID()
        remote.historyRows = [PendingRakugakiDTO(
            id: rakugakiID, photoId: photoID, authorId: context.userID,
            authorName: nil, authorAvatarPath: nil,
            assetPath: "owner/rakugakis/drawing.png", status: .approved,
            createdAt: nil)]
        let repository = ARRepository(remote: remote, photos: PersistentARTestPhotos(),
                                      session: session, worldMaps: store)
        let package = try XCTUnwrap(PersistentARPackage(
            data: Data([1, 2, 3]),
            anchorName: "rakugaki:00000000-0000-0000-0000-000000000001",
            displayWidthM: 1, formatVersion: 1))

        do {
            _ = try await repository.publishPersistent(
                package: package, photoID: photoID, rakugakiID: rakugakiID,
                unlockRadiusM: 50, discoveryRadiusM: 150,
                fallbackAltitudeM: nil, fallbackHeadingDeg: nil,
                context: context)
            XCTFail("RPC失敗を返す必要があります")
        } catch let failure as AppFailure {
            XCTAssertEqual(failure, .serviceUnavailable)
        }

        XCTAssertEqual(store.deleted, [store.uploaded])
    }
}

@MainActor
private final class PersistentARTestStore: ARWorldMapStoring {
    let uploaded = AssetReference(
        bucket: "ar-world-maps",
        path: "00000000-0000-0000-0000-000000000001/world-maps/00000000-0000-0000-0000-000000000002.armap")!
    private(set) var deleted: [AssetReference] = []

    func upload(package: PersistentARPackage, context: SessionContext) async throws -> AssetReference {
        uploaded
    }
    func download(asset: AssetReference, context: SessionContext) async throws -> Data { Data() }
    func delete(asset: AssetReference, context: SessionContext) async throws { deleted.append(asset) }
}

private actor PersistentARTestSession: SessionProviding {
    let context: SessionContext
    init(_ context: SessionContext) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}

@MainActor
private final class PersistentARTestPhotos: PhotoReading {
    func nearby(center: GeoPoint, radiusM: Double) async throws -> [Photo] { [] }
    func permissions(photoID: UUID) async throws -> PhotoPermissions {
        PhotoPermissions(canView: true, canDraw: true, isOwner: true)
    }
}

@MainActor
private final class PersistentARTestRemote: ARRemoteCalling {
    var historyRows: [PendingRakugakiDTO] = []
    func experience(photoID: UUID) async throws -> [ArExperienceDTO] { [] }
    func nearbyTraces(at point: GeoPoint) async throws -> [NearbyArTraceDTO] { [] }
    func publish(_ request: CreateArExperienceRequestDTO) async throws -> ArExperienceRowDTO {
        throw AppFailure.serviceUnavailable
    }
    func publishPersistent(_ request: PublishPersistentARRequestDTO) async throws -> ArExperienceRowDTO {
        throw AppFailure.serviceUnavailable
    }
    func history(photoID: UUID) async throws -> [PendingRakugakiDTO] { historyRows }
}
