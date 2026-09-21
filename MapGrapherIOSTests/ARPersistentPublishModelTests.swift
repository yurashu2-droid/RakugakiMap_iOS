import Foundation
import MapGrapherCore
import XCTest
@testable import MapGrapherIOS

@MainActor
final class ARPersistentPublishModelTests: XCTestCase {
    func testCaptureAndUploadReachPublishedOnce() async throws {
        let model = ARPersistentPublishModel()
        let package = try makePackage()
        let experience = try makeExperience()
        var captureCalls = 0
        var uploadCalls = 0

        await model.publish(capture: {
            captureCalls += 1
            return package
        }, upload: { received in
            uploadCalls += 1
            XCTAssertEqual(received, package)
            return experience
        })

        XCTAssertEqual(model.state, .published)
        XCTAssertEqual(captureCalls, 1)
        XCTAssertEqual(uploadCalls, 1)
    }

    func testUploadFailureRetainsPackageForRetry() async throws {
        let model = ARPersistentPublishModel()
        let package = try makePackage()
        let experience = try makeExperience()
        var captureCalls = 0
        var uploadCalls = 0

        await model.publish(capture: {
            captureCalls += 1
            return package
        }, upload: { _ in
            uploadCalls += 1
            throw AppFailure.offline
        })
        XCTAssertEqual(model.state, .failed(retryable: true))
        XCTAssertTrue(model.hasCapturedPackage)

        await model.publish(capture: {
            captureCalls += 1
            return package
        }, upload: { _ in
            uploadCalls += 1
            return experience
        })

        XCTAssertEqual(model.state, .published)
        XCTAssertEqual(captureCalls, 1)
        XCTAssertEqual(uploadCalls, 2)
    }

    func testSessionInvalidationClearsCapturedPackage() async throws {
        let model = ARPersistentPublishModel()
        let package = try makePackage()
        await model.publish(capture: { package }, upload: { _ in throw AppFailure.offline })
        XCTAssertTrue(model.hasCapturedPackage)

        model.cancelSession()

        XCTAssertFalse(model.hasCapturedPackage)
        XCTAssertEqual(model.state, .scanning)
    }

    private func makePackage() throws -> PersistentARPackage {
        try XCTUnwrap(PersistentARPackage(
            data: Data([1]),
            anchorName: "rakugaki:00000000-0000-0000-0000-000000000001",
            displayWidthM: 1))
    }

    private func makeExperience() throws -> ArExperience {
        try XCTUnwrap(ArExperience(
            id: UUID(), photoID: UUID(), rakugakiID: UUID(),
            asset: try XCTUnwrap(AssetReference(
                bucket: "rakugakis", path: "owner/rakugakis/drawing.png")),
            unlockRadiusM: 50, discoveryRadiusM: 150, displayWidthM: 1,
            location: try XCTUnwrap(GeoPoint(latitude: 35, longitude: 139)),
            anchorType: .worldMapV1,
            worldMap: try XCTUnwrap(AssetReference(
                bucket: "ar-world-maps", path: "owner/world-maps/map.armap")),
            anchorName: "rakugaki:00000000-0000-0000-0000-000000000001",
            worldMapFormatVersion: 1))
    }
}
