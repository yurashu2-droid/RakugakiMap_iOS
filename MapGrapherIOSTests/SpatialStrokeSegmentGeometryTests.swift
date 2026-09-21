import XCTest
import simd
@testable import MapGrapherIOS

final class SpatialStrokeSegmentGeometryTests: XCTestCase {
    func testBuildsMidpointLengthAndRotationFromYAxis() throws {
        let geometry = try XCTUnwrap(SpatialStrokeSegmentGeometry(
            start: SIMD3<Float>(0, 1, 2),
            end: SIMD3<Float>(0, 1, 3),
            radius: 0.015
        ))

        XCTAssertEqual(geometry.center.x, 0, accuracy: 0.0001)
        XCTAssertEqual(geometry.center.y, 1, accuracy: 0.0001)
        XCTAssertEqual(geometry.center.z, 2.5, accuracy: 0.0001)
        XCTAssertEqual(geometry.length, 1, accuracy: 0.0001)
        XCTAssertEqual(geometry.radius, 0.015, accuracy: 0.0001)

        let rotatedAxis = geometry.orientation.act(SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(rotatedAxis.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rotatedAxis.y, 0, accuracy: 0.0001)
        XCTAssertEqual(rotatedAxis.z, 1, accuracy: 0.0001)
    }

    func testSupportsOppositeYAxisWithoutProducingNaN() throws {
        let geometry = try XCTUnwrap(SpatialStrokeSegmentGeometry(
            start: SIMD3<Float>(0, 1, 0),
            end: SIMD3<Float>(0, 0, 0),
            radius: 0.01
        ))

        let rotatedAxis = geometry.orientation.act(SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(rotatedAxis.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rotatedAxis.y, -1, accuracy: 0.0001)
        XCTAssertEqual(rotatedAxis.z, 0, accuracy: 0.0001)
        XCTAssertTrue(geometry.orientation.vector.x.isFinite)
        XCTAssertTrue(geometry.orientation.vector.y.isFinite)
        XCTAssertTrue(geometry.orientation.vector.z.isFinite)
        XCTAssertTrue(geometry.orientation.vector.w.isFinite)
    }

    func testRejectsDegenerateOrUnsafeInput() {
        XCTAssertNil(SpatialStrokeSegmentGeometry(start: .zero, end: .zero, radius: 0.01))
        XCTAssertNil(SpatialStrokeSegmentGeometry(
            start: SIMD3<Float>(.nan, 0, 0), end: SIMD3<Float>(1, 0, 0), radius: 0.01
        ))
        XCTAssertNil(SpatialStrokeSegmentGeometry(
            start: .zero, end: SIMD3<Float>(1, 0, 0), radius: 0
        ))
        XCTAssertNil(SpatialStrokeSegmentGeometry(
            start: .zero, end: SIMD3<Float>(1, 0, 0), radius: .infinity
        ))
    }
}
