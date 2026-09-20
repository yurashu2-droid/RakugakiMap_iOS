import XCTest

@MainActor
final class PostingUITests: XCTestCase {
    private enum UI {
        static let launchArgument = "--ui-testing"
        static let mapScreen = "screen.map"
        static let captureScreen = "screen.posting.capture"
        static let reviewScreen = "screen.posting.review"
        static let drawingScreen = "screen.posting.drawing"
        static let publishScreen = "screen.posting.publish"
        static let statusScreen = "screen.posting.status"
    }

    func testPostingFlowReachesWaitingStatusWithoutClaimingSuccess() throws {
        let app = launchApp()

        XCTAssertTrue(screen(UI.mapScreen, in: app).waitForExistence(timeout: 5))
        app.buttons["map.post.button"].tap()
        XCTAssertTrue(screen(UI.captureScreen, in: app).waitForExistence(timeout: 5))

        app.buttons["posting.capture.test-fixture"].tap()
        XCTAssertTrue(screen(UI.reviewScreen, in: app).waitForExistence(timeout: 5))
        app.buttons["posting.review.continue"].tap()
        XCTAssertTrue(screen(UI.drawingScreen, in: app).waitForExistence(timeout: 5))
        app.buttons["posting.drawing.skip"].tap()
        XCTAssertTrue(screen(UI.publishScreen, in: app).waitForExistence(timeout: 5))

        let title = app.textFields["posting.publish.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Test post")
        app.buttons["posting.publish.submit"].tap()
        XCTAssertTrue(screen(UI.statusScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["posting.status.waiting"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["posting.status.success"].exists)
    }

    func testBackKeepsDraftAndReturnsToPreviousStep() throws {
        let app = launchApp()

        app.buttons["map.post.button"].tap()
        XCTAssertTrue(screen(UI.captureScreen, in: app).waitForExistence(timeout: 5))
        app.buttons["posting.capture.test-fixture"].tap()
        XCTAssertTrue(screen(UI.reviewScreen, in: app).waitForExistence(timeout: 5))
        app.buttons["posting.review.continue"].tap()
        XCTAssertTrue(screen(UI.drawingScreen, in: app).waitForExistence(timeout: 5))

        app.buttons["posting.flow.back"].tap()
        XCTAssertTrue(screen(UI.reviewScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["posting.review.continue"].exists)
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [UI.launchArgument]
        app.launch()
        return app
    }

    private func screen(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
