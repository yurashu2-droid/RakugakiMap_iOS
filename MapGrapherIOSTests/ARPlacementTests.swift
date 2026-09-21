import XCTest
@testable import MapGrapherIOS

final class ARPlacementTests: XCTestCase {
    func testScaleClampsDisplayWidthToPublishedLimits() throws {
        let placement = try XCTUnwrap(ARPlacement(
            position: .zero,
            yawRadians: 0,
            displayWidthM: 1
        ))

        XCTAssertEqual(placement.scaled(by: 100).displayWidthM, 10)
        XCTAssertEqual(placement.scaled(by: 0.001).displayWidthM, 0.1)
    }

    func testRotationNormalizesFiniteYaw() throws {
        let placement = try XCTUnwrap(ARPlacement(
            position: .zero,
            yawRadians: 0,
            displayWidthM: 1
        ))

        XCTAssertEqual(
            placement.rotated(by: .pi * 3).yawRadians,
            -.pi,
            accuracy: 0.0001
        )
        XCTAssertNil(ARPlacement(
            position: .zero,
            yawRadians: .infinity,
            displayWidthM: 1
        ))
    }

    func testNonFiniteScaleDoesNotCorruptPlacement() throws {
        let placement = try XCTUnwrap(ARPlacement(
            position: .zero,
            yawRadians: 0,
            displayWidthM: 1
        ))

        XCTAssertEqual(placement.scaled(by: .infinity), placement)
        XCTAssertEqual(placement.scaled(by: .nan), placement)
    }

    func testNonFinitePositionIsRejected() {
        XCTAssertNil(ARPlacement(
            position: SIMD3<Float>(.infinity, 0, 0),
            yawRadians: 0,
            displayWidthM: 1
        ))
    }
}
