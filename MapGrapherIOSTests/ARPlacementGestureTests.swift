import XCTest
@testable import MapGrapherIOS

final class ARPlacementGestureTests: XCTestCase {
    func testPinchIsIgnoredAfterPlacementIsLocked() throws {
        var editor = ARPlacementEditor(initial: try makePlacement())

        editor.lock()
        editor.scale(by: 2)

        XCTAssertEqual(editor.placement.displayWidthM, 1)
        XCTAssertEqual(editor.state, .locked)
    }

    func testEditingAllowsMoveScaleAndRotation() throws {
        var editor = ARPlacementEditor(initial: try makePlacement())

        editor.move(to: SIMD3<Float>(1, 2, 3))
        editor.scale(by: 1.5)
        editor.rotate(by: .pi / 2)

        XCTAssertEqual(editor.placement.position, SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(editor.placement.displayWidthM, 1.5)
        XCTAssertEqual(editor.placement.yawRadians, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(editor.state, .editing)
    }

    func testUnlockReturnsToEditingWithoutChangingPlacement() throws {
        var editor = ARPlacementEditor(initial: try makePlacement())
        editor.scale(by: 2)
        editor.lock()

        editor.unlock()

        XCTAssertEqual(editor.state, .editing)
        XCTAssertEqual(editor.placement.displayWidthM, 2)
    }

    private func makePlacement() throws -> ARPlacement {
        try XCTUnwrap(ARPlacement(
            position: .zero,
            yawRadians: 0,
            displayWidthM: 1
        ))
    }
}
