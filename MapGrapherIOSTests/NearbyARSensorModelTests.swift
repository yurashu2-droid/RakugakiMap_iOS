import Foundation
import MapGrapherCore
import XCTest
@testable import MapGrapherIOS

/// 地図の「ARの気配メーター」が、近さ・向き・見られる距離を正しく出すか。
/// 位置・コンパス・サーバーは偽物で、実機のGPSやコンパスの動きはここでは確かめられない。
@MainActor
final class NearbyARSensorModelTests: XCTestCase {
    func testBeyondDiscoveryRadiusShowsNothing() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(metersSouth: 300, fixture.now))
        try await eventually { fixture.repository.nearbyCalls == 1 }
        XCTAssertEqual(fixture.model.strength, 0)
        XCTAssertNil(fixture.model.openableTrace)
        XCTAssertNil(fixture.model.arrowDegrees)
    }

    func testStrengthRisesAsUserGetsCloser() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(metersSouth: 120, fixture.now))
        try await eventually { fixture.model.strength == 1 }
        XCTAssertNil(fixture.model.openableTrace)

        fixture.location.send(sample(metersSouth: 70, fixture.now.addingTimeInterval(0.1)))
        try await eventually { fixture.model.strength == 2 }
        XCTAssertNil(fixture.model.openableTrace)

        // 解放半径（50m）に入ると、見られるARとして出す
        fixture.location.send(sample(metersSouth: 30, fixture.now.addingTimeInterval(0.2)))
        try await eventually { fixture.model.strength == 3 }
        XCTAssertEqual(fixture.model.openableTrace?.id, fixture.trace.id)

        fixture.location.send(sample(metersSouth: 8, fixture.now.addingTimeInterval(0.3)))
        try await eventually { fixture.model.strength == 4 }
        XCTAssertEqual(fixture.model.openableTrace?.id, fixture.trace.id)
        // 位置が少し動いただけでは、サーバーへ問い合わせ直さない
        XCTAssertEqual(fixture.repository.nearbyCalls, 1)
    }

    func testSmallJitterAtBoundaryDoesNotFlipStrength() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(metersSouth: 52, fixture.now))
        try await eventually { fixture.model.strength == 2 }
        // 境目（50m）を3mだけまたいでも、段階は変えない
        fixture.location.send(sample(metersSouth: 49, fixture.now.addingTimeInterval(0.1)))
        try await eventually { fixture.model.openableTrace != nil }
        XCTAssertEqual(fixture.model.strength, 2)
        fixture.location.send(sample(metersSouth: 44, fixture.now.addingTimeInterval(0.2)))
        try await eventually { fixture.model.strength == 3 }
    }

    func testArrowPointsRelativeToHeading() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        // ARは利用者の真北にある。東（90度）を向いていると、ARは左90度に見える
        fixture.location.send(sample(metersSouth: 70, fixture.now))
        try await eventually { fixture.model.strength == 2 }
        XCTAssertNil(fixture.model.arrowDegrees)
        fixture.heading.send(TrueHeadingSample(degrees: 90, accuracyDegrees: 10, timestamp: fixture.now))
        try await eventually { fixture.model.arrowDegrees != nil }
        XCTAssertEqual(try XCTUnwrap(fixture.model.arrowDegrees), -90, accuracy: 0.5)

        // 向きの精度が粗いときは矢印を出さない
        fixture.heading.send(TrueHeadingSample(degrees: 90, accuracyDegrees: 60, timestamp: fixture.now))
        try await eventually { fixture.model.arrowDegrees == nil }
    }

    func testArrowIsHiddenWhileFarAway() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(metersSouth: 120, fixture.now))
        try await eventually { fixture.model.strength == 1 }
        fixture.heading.send(TrueHeadingSample(degrees: 90, accuracyDegrees: 10, timestamp: fixture.now))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(fixture.model.arrowDegrees)
    }

    func testCoarseAndOldSamplesAreIgnored() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(metersSouth: 30, fixture.now, accuracy: 40))
        fixture.location.send(sample(metersSouth: 30, fixture.now.addingTimeInterval(-30)))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.repository.nearbyCalls, 0)
        XCTAssertEqual(fixture.model.strength, 0)
    }

    func testDoesNotStartOrPromptWithoutLocationPermission() {
        for access in [ARLocationAccess.notDetermined, .reducedAccuracy, .denied] {
            let fixture = makeFixture(access: access)
            fixture.model.start()
            XCTAssertFalse(fixture.model.isRunning)
            XCTAssertEqual(fixture.location.startCount, 0)
            XCTAssertEqual(fixture.heading.startCount, 0)
        }
    }

    func testSessionSwitchStopsAndClearsReading() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(metersSouth: 30, fixture.now))
        try await eventually { fixture.model.openableTrace != nil }
        await fixture.session.set(SessionContext(userID: UUID(), epoch: UUID()))
        fixture.location.send(sample(metersSouth: 30, fixture.now.addingTimeInterval(0.1)))
        try await eventually { !fixture.model.isRunning }
        XCTAssertEqual(fixture.model.strength, 0)
        XCTAssertNil(fixture.model.openableTrace)
    }

    func testStopClearsReadingAndStopsSensors() async throws {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.location.send(sample(metersSouth: 30, fixture.now))
        try await eventually { fixture.model.strength == 3 }
        fixture.model.stop()
        XCTAssertEqual(fixture.model.strength, 0)
        XCTAssertNil(fixture.model.openableTrace)
        XCTAssertEqual(fixture.location.stopCount, 1)
        XCTAssertEqual(fixture.heading.stopCount, 1)
    }

    func testFixedModelKeepsItsReading() {
        let trace = makeTrace()
        let model = NearbyARSensorModel.fixed(strength: 3, arrowDegrees: 40, openableTrace: trace)
        model.start()
        model.stop()
        XCTAssertEqual(model.strength, 3)
        XCTAssertEqual(model.arrowDegrees, 40)
        XCTAssertEqual(model.openableTrace, trace)
    }

    // MARK: - 準備

    /// ARの場所（北緯35度・東経139度）から、真南へ指定の距離だけ離れた地点の測位
    private func sample(metersSouth: Double, _ timestamp: Date, accuracy: Double = 5) -> LocationSample {
        // 緯度1度は約111,195m（距離の計算と同じ地球の半径6,371,000mから）
        let point = GeoPoint(latitude: 35 - metersSouth / 111_194.93, longitude: 139)!
        return LocationSample(point: point, horizontalAccuracyM: accuracy, timestamp: timestamp)!
    }

    private func makeTrace() -> ARTrace {
        ARTrace(id: UUID(), photoID: UUID(), location: GeoPoint(latitude: 35, longitude: 139)!,
                unlockRadiusM: 50, discoveryRadiusM: 150, distanceM: 0,
                createdAt: Date(timeIntervalSince1970: 30_000), anchorType: .localPlane)!
    }

    private func makeFixture(access: ARLocationAccess = .allowed) -> SensorFixture {
        let now = Date(timeIntervalSince1970: 30_000)
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let trace = makeTrace()
        let location = SensorTestLocation(access: access)
        let heading = SensorTestHeading()
        let repository = SensorTestRepository(traces: [trace])
        let session = SensorTestSession(context)
        let model = NearbyARSensorModel(
            services: NearbyARSensorModel.Services(
                context: context, repository: repository, location: location,
                heading: heading, session: session),
            clock: { now.addingTimeInterval(1) })
        return SensorFixture(now: now, trace: trace, model: model, location: location,
                             heading: heading, repository: repository, session: session)
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("期待した気配メーターの状態へ移行しませんでした")
    }
}

@MainActor
private struct SensorFixture {
    let now: Date
    let trace: ARTrace
    let model: NearbyARSensorModel
    let location: SensorTestLocation
    let heading: SensorTestHeading
    let repository: SensorTestRepository
    let session: SensorTestSession
}

@MainActor
private final class SensorTestLocation: ARLocationProviding {
    var access: ARLocationAccess
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var continuation: AsyncStream<LocationSample>.Continuation?
    init(access: ARLocationAccess) { self.access = access }
    func updates() -> AsyncStream<LocationSample> {
        let pair = AsyncStream.makeStream(of: LocationSample.self)
        continuation = pair.continuation
        return pair.stream
    }
    func start() { startCount += 1 }
    func stop() { stopCount += 1; continuation?.finish(); continuation = nil }
    func send(_ sample: LocationSample) { continuation?.yield(sample) }
}

@MainActor
private final class SensorTestHeading: HeadingProviding {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var continuation: AsyncStream<TrueHeadingSample>.Continuation?
    func updates() -> AsyncStream<TrueHeadingSample> {
        let pair = AsyncStream.makeStream(of: TrueHeadingSample.self)
        continuation = pair.continuation
        return pair.stream
    }
    func start() { startCount += 1 }
    func stop() { stopCount += 1; continuation?.finish(); continuation = nil }
    func send(_ sample: TrueHeadingSample) { continuation?.yield(sample) }
}

@MainActor
private final class SensorTestRepository: ARExperienceServing {
    let traces: [ARTrace]
    private(set) var nearbyCalls = 0
    init(traces: [ARTrace]) { self.traces = traces }
    func experience(photoID: UUID, context: SessionContext) async throws -> ArExperience {
        throw AppFailure.notFound
    }
    func nearbyTraces(at point: GeoPoint, context: SessionContext) async throws -> [ARTrace] {
        nearbyCalls += 1
        return traces
    }
    func publish(photoID: UUID, rakugakiID: UUID, unlockRadiusM: Double,
                 discoveryRadiusM: Double, displayWidthM: Double,
                 context: SessionContext) async throws -> ArExperience {
        throw AppFailure.serviceUnavailable
    }
}

private actor SensorTestSession: SessionProviding {
    var context: SessionContext?
    init(_ context: SessionContext) { self.context = context }
    func set(_ context: SessionContext?) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}
