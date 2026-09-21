import XCTest

@MainActor
final class SpatialARDrawingUITests: XCTestCase {
    func testOpensIndependentSpatialDrawingModeFromMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let entry = app.buttons["map.spatial-ar-drawing.button"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(element("screen.spatial-ar-drawing", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["spatial-ar.draw.button"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.undo.button"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.clear.button"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.close.button"].exists)
        XCTAssertFalse(element("screen.posting.capture", in: app).exists)
    }

    func testSpatialDrawingOffersColorAndWidthControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["map.spatial-ar-drawing.button"].tap()

        XCTAssertTrue(app.buttons["spatial-ar.color.coral"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["spatial-ar.color.cyan"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.color.yellow"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.color.white"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.width.0.01"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.width.0.03"].exists)
        XCTAssertTrue(app.buttons["spatial-ar.width.0.06"].exists)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
