import XCTest

@MainActor
final class MapUITests: XCTestCase {
    private enum UI {
        static let launchArgument = "--ui-testing"
        static let mapScreen = "screen.map"
        static let photoListButton = "map.photo-list.button"
        static let photoListScreen = "screen.photo-list"
        static let photoDetailScreen = "screen.photo-detail"
        static let photoRow = "map.photo-row"
        static let arButton = "photo.ar.button"
    }

    func testMapOffersFiltersAndPhotoList() throws {
        let app = launchApp()

        XCTAssertTrue(screen(UI.mapScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map.filter.all"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map.filter.friends"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map.filter.recent"].waitForExistence(timeout: 5))

        app.buttons[UI.photoListButton].tap()
        XCTAssertTrue(screen(UI.photoListScreen, in: app).waitForExistence(timeout: 5))
    }

    func testSelectingPhotoOpensDetailAndProvidesARAction() throws {
        let app = launchApp()

        XCTAssertTrue(screen(UI.mapScreen, in: app).waitForExistence(timeout: 5))
        app.buttons[UI.photoListButton].tap()
        XCTAssertTrue(screen(UI.photoListScreen, in: app).waitForExistence(timeout: 5))

        let firstPhoto = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", UI.photoRow)
        ).firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 5))
        firstPhoto.tap()

        XCTAssertTrue(app.otherElements[UI.photoDetailScreen].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[UI.arButton].waitForExistence(timeout: 5))
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
