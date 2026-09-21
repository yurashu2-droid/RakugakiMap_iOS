import XCTest
import simd
@testable import MapGrapherIOS

final class SpatialPenTipModeTests: XCTestCase {
    func testCameraBodyUsesCameraTranslation() throws {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(1.2, -0.4, 3.5, 1)

        let position = try XCTUnwrap(
            SpatialPenTipMode.cameraBody.position(cameraTransform: transform)
        )

        XCTAssertEqual(position.x, 1.2, accuracy: 0.0001)
        XCTAssertEqual(position.y, -0.4, accuracy: 0.0001)
        XCTAssertEqual(position.z, 3.5, accuracy: 0.0001)
    }

    func testCameraForwardUsesPointThirtyCentimetersAlongNegativeZ() throws {
        let position = try XCTUnwrap(
            SpatialPenTipMode.cameraForward.position(cameraTransform: matrix_identity_float4x4)
        )

        XCTAssertEqual(position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(position.y, 0, accuracy: 0.0001)
        XCTAssertEqual(position.z, -0.3, accuracy: 0.0001)
    }

    func testCameraForwardFollowsCameraRotationAndTranslation() throws {
        var transform = simd_float4x4(simd_quatf(
            angle: .pi / 2,
            axis: SIMD3<Float>(0, 1, 0)
        ))
        transform.columns.3 = SIMD4<Float>(2, 1, 4, 1)

        let position = try XCTUnwrap(
            SpatialPenTipMode.cameraForward.position(cameraTransform: transform)
        )

        XCTAssertEqual(position.x, 1.7, accuracy: 0.0001)
        XCTAssertEqual(position.y, 1, accuracy: 0.0001)
        XCTAssertEqual(position.z, 4, accuracy: 0.0001)
    }

    func testRejectsNonFiniteCameraTransform() {
        var transform = matrix_identity_float4x4
        transform.columns.2.z = .nan

        XCTAssertNil(SpatialPenTipMode.cameraBody.position(cameraTransform: transform))
        XCTAssertNil(SpatialPenTipMode.cameraForward.position(cameraTransform: transform))
    }
}
