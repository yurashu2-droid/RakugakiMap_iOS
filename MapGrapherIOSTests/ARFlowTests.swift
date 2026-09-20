import Foundation
import MapGrapherCore
import UIKit
import XCTest
@testable import MapGrapherIOS

@MainActor
final class ARFlowTests: XCTestCase {
    func testTwoFreshNearbySamplesLoadPrivateImage() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(fixture.now, accuracy: 5))
        fixture.location.send(sample(fixture.now.addingTimeInterval(1), accuracy: 5))
        try await eventually { fixture.model.state == .ready }
        XCTAssertNotNil(fixture.model.image)
        XCTAssertEqual(fixture.loader.calls, 1)
        XCTAssertEqual(fixture.repository.experienceCalls, 1)
    }

    func testFarInaccurateAndOldSamplesNeverUnlock() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(fixture.now.addingTimeInterval(-11), accuracy: 5))
        fixture.location.send(sample(fixture.now, accuracy: 30))
        let far = GeoPoint(latitude: 35.01, longitude: 139)!
        fixture.location.send(LocationSample(point: far, horizontalAccuracyM: 5,
                                             timestamp: fixture.now.addingTimeInterval(1))!)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotEqual(fixture.model.state, .ready)
        XCTAssertEqual(fixture.loader.calls, 0)
        XCTAssertEqual(fixture.repository.experienceCalls, 0)
    }

    func testDeniedAndReducedLocationCannotUnlock() async throws {
        let denied = makeFixture(access: .denied)
        denied.model.start()
        XCTAssertEqual(denied.model.state, .locationDenied)
        let reduced = makeFixture(access: .reducedAccuracy)
        reduced.model.start()
        reduced.location.send(sample(reduced.now, accuracy: 5))
        reduced.location.send(sample(reduced.now.addingTimeInterval(1), accuracy: 5))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reduced.model.state, .locationImprecise)
        XCTAssertEqual(reduced.loader.calls, 0)
    }

    func testEpochSwitchDiscardsLateImage() async throws {
        let fixture = makeFixture()
        fixture.loader.waitForRelease = true
        fixture.model.start()
        fixture.location.send(sample(fixture.now, accuracy: 5))
        fixture.location.send(sample(fixture.now.addingTimeInterval(1), accuracy: 5))
        try await eventually { fixture.model.state == .loadingImage }
        await fixture.session.set(SessionContext(userID: fixture.context.userID, epoch: UUID()))
        fixture.loader.release()
        try await eventually { fixture.model.state == .unavailable }
        XCTAssertNil(fixture.model.image)
    }

    func testImageRefreshFailureClearsPreviouslyVisibleAsset() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(fixture.now, accuracy: 5))
        fixture.location.send(sample(fixture.now.addingTimeInterval(1), accuracy: 5))
        try await eventually { fixture.model.state == .ready }
        fixture.loader.failNext = true
        await fixture.model.refresh()
        fixture.location.send(sample(fixture.now.addingTimeInterval(2), accuracy: 5))
        fixture.location.send(sample(fixture.now.addingTimeInterval(3), accuracy: 5))
        try await eventually { fixture.model.state == .unavailable }
        XCTAssertNil(fixture.model.image)
    }

    func testPendingRakugakiIsNotPublished() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = ARTestSession(context)
        let remote = ARTestRemote()
        let photoID = UUID()
        let rakugakiID = UUID()
        remote.historyRows = [PendingRakugakiDTO(id: rakugakiID, photoId: photoID,
            authorId: context.userID, authorName: nil, authorAvatarPath: nil,
            assetPath: "drawing.png", status: .pending, createdAt: nil)]
        let repository = ARRepository(remote: remote,
                                      photos: ARTestPhotos(), session: session)
        do {
            _ = try await repository.publish(photoID: photoID, rakugakiID: rakugakiID,
                unlockRadiusM: 50, discoveryRadiusM: 150,
                displayWidthM: 1, context: context)
            XCTFail("承認待ちを公開成功にしてはいけません")
        } catch let failure as AppFailure {
            if case .validation = failure {} else { XCTFail("validationが必要です") }
        }
        XCTAssertEqual(remote.publishCalls, 0)
    }

    private func sample(_ timestamp: Date, accuracy: Double) -> LocationSample {
        LocationSample(point: GeoPoint(latitude: 35, longitude: 139)!,
                       horizontalAccuracyM: accuracy, timestamp: timestamp)!
    }

    private func makeFixture(access: ARLocationAccess = .allowed) -> ARFixture {
        let now = Date(timeIntervalSince1970: 20_000)
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let point = GeoPoint(latitude: 35, longitude: 139)!
        let trace = ARTrace(id: UUID(), photoID: UUID(), location: point,
            unlockRadiusM: 50, discoveryRadiusM: 150, distanceM: 0,
            createdAt: now, anchorType: .localPlane)!
        let asset = AssetReference(bucket: "rakugakis", path: "owner/rakugakis/drawing.png")!
        let experience = ArExperience(id: trace.id, photoID: trace.photoID,
            rakugakiID: UUID(), asset: asset, unlockRadiusM: 50,
            discoveryRadiusM: 150, displayWidthM: 1, location: point,
            anchorType: .localPlane)!
        let location = ARTestLocation(access: access)
        let repository = ARTestRepository(experience: experience)
        let loader = ARTestImageLoader()
        let session = ARTestSession(context)
        let model = ARScreenModel(trace: trace, context: context, repository: repository,
            imageLoader: loader, location: location, session: session,
            clock: { now.addingTimeInterval(4) })
        return ARFixture(now: now, context: context, model: model,
                         location: location, repository: repository,
                         loader: loader, session: session)
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("期待したAR状態へ移行しませんでした")
    }
}

@MainActor
private struct ARFixture {
    let now: Date
    let context: SessionContext
    let model: ARScreenModel
    let location: ARTestLocation
    let repository: ARTestRepository
    let loader: ARTestImageLoader
    let session: ARTestSession
}

@MainActor
private final class ARTestLocation: ARLocationProviding {
    var access: ARLocationAccess
    private var continuation: AsyncStream<LocationSample>.Continuation?
    init(access: ARLocationAccess) { self.access = access }
    func updates() -> AsyncStream<LocationSample> {
        let pair = AsyncStream.makeStream(of: LocationSample.self)
        continuation = pair.continuation
        return pair.stream
    }
    func start() {}
    func stop() { continuation?.finish(); continuation = nil }
    func send(_ sample: LocationSample) { continuation?.yield(sample) }
}

@MainActor
private final class ARTestRepository: ARExperienceServing {
    let value: ArExperience
    var experienceCalls = 0
    init(experience: ArExperience) { value = experience }
    func experience(photoID: UUID, context: SessionContext) async throws -> ArExperience {
        experienceCalls += 1
        return value
    }
    func nearbyTraces(at point: GeoPoint, context: SessionContext) async throws -> [ARTrace] { [] }
    func publish(photoID: UUID, rakugakiID: UUID, unlockRadiusM: Double,
                 discoveryRadiusM: Double, displayWidthM: Double,
                 context: SessionContext) async throws -> ArExperience { value }
}

@MainActor
private final class ARTestImageLoader: ARImageLoading {
    var calls = 0
    var failNext = false
    var waitForRelease = false
    private var continuation: CheckedContinuation<Void, Never>?
    func load(asset: AssetReference, targetPixelSize: CGSize,
              context: SessionContext) async throws -> UIImage {
        calls += 1
        if waitForRelease {
            await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
                continuation = pending
            }
            waitForRelease = false
        }
        if failNext { failNext = false; throw AppFailure.serviceUnavailable }
        return UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor ARTestSession: SessionProviding {
    var context: SessionContext?
    init(_ context: SessionContext) { self.context = context }
    func set(_ context: SessionContext?) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}

@MainActor
private final class ARTestPhotos: PhotoReading {
    func nearby(center: GeoPoint, radiusM: Double) async throws -> [Photo] { [] }
    func permissions(photoID: UUID) async throws -> PhotoPermissions {
        PhotoPermissions(canView: true, canDraw: true, isOwner: true)
    }
}

@MainActor
private final class ARTestRemote: ARRemoteCalling {
    var historyRows: [PendingRakugakiDTO] = []
    var publishCalls = 0
    func experience(photoID: UUID) async throws -> [ArExperienceDTO] { [] }
    func nearbyTraces(at point: GeoPoint) async throws -> [NearbyArTraceDTO] { [] }
    func publish(_ request: CreateArExperienceRequestDTO) async throws -> ArExperienceRowDTO {
        publishCalls += 1
        throw AppFailure.serviceUnavailable
    }
    func history(photoID: UUID) async throws -> [PendingRakugakiDTO] { historyRows }
}
