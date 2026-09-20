import XCTest
@testable import MapGrapherIOS

final class ARPlaneGeometryTests: XCTestCase {
    func testLandscapeImageKeepsAspectRatioAtOneMeterWidth() throws {
        let plane = try ARPlaneGeometry(
            pixelWidth: 1_000, pixelHeight: 500, displayWidthM: 1
        )

        XCTAssertEqual(plane.widthM, 1, accuracy: 0.000_001)
        XCTAssertEqual(plane.heightM, 0.5, accuracy: 0.000_001)
    }

    func testPortraitImageKeepsAspectRatio() throws {
        let plane = try ARPlaneGeometry(
            pixelWidth: 500, pixelHeight: 1_000, displayWidthM: 0.8
        )

        XCTAssertEqual(plane.widthM, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(plane.heightM, 1.6, accuracy: 0.000_001)
    }

    func testDisplayWidthRangeIncludesItsBoundaries() throws {
        let minimum = try ARPlaneGeometry(
            pixelWidth: 1_000, pixelHeight: 500, displayWidthM: 0.1
        )
        let maximum = try ARPlaneGeometry(
            pixelWidth: 1_000, pixelHeight: 500, displayWidthM: 10
        )

        XCTAssertEqual(minimum.heightM, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(maximum.heightM, 5, accuracy: 0.000_001)
    }

    func testZeroAndNegativeDimensionsAreRejected() {
        let cases: [(name: String, width: Double, height: Double, displayWidth: Double)] = [
            ("画像幅ゼロ", 0, 500, 1),
            ("画像高さゼロ", 1_000, 0, 1),
            ("画像幅が負", -1_000, 500, 1),
            ("画像高さが負", 1_000, -500, 1),
            ("実幅ゼロ", 1_000, 500, 0),
            ("実幅が負", 1_000, 500, -1),
        ]

        for sample in cases {
            XCTAssertThrowsError(try ARPlaneGeometry(
                pixelWidth: sample.width,
                pixelHeight: sample.height,
                displayWidthM: sample.displayWidth
            ), sample.name)
        }
    }

    func testDisplayWidthOutsidePublishedRangeIsRejected() {
        XCTAssertThrowsError(try ARPlaneGeometry(
            pixelWidth: 1_000, pixelHeight: 500, displayWidthM: 0.099
        ))
        XCTAssertThrowsError(try ARPlaneGeometry(
            pixelWidth: 1_000, pixelHeight: 500, displayWidthM: 10.001
        ))
    }

    func testNonFiniteInputsAreRejected() {
        let cases: [(name: String, width: Double, height: Double, displayWidth: Double)] = [
            ("画像幅NaN", .nan, 500, 1),
            ("画像幅無限大", .infinity, 500, 1),
            ("画像高さNaN", 1_000, .nan, 1),
            ("画像高さ無限大", 1_000, .infinity, 1),
            ("実幅NaN", 1_000, 500, .nan),
            ("実幅無限大", 1_000, 500, .infinity),
        ]

        for sample in cases {
            XCTAssertThrowsError(try ARPlaneGeometry(
                pixelWidth: sample.width,
                pixelHeight: sample.height,
                displayWidthM: sample.displayWidth
            ), sample.name)
        }
    }

    func testHeightOverflowAndUnderflowAreRejected() {
        XCTAssertThrowsError(try ARPlaneGeometry(
            pixelWidth: 1,
            pixelHeight: .greatestFiniteMagnitude,
            displayWidthM: 10
        ))
        XCTAssertThrowsError(try ARPlaneGeometry(
            pixelWidth: .greatestFiniteMagnitude,
            pixelHeight: .leastNonzeroMagnitude,
            displayWidthM: 0.1
        ))
    }
}
