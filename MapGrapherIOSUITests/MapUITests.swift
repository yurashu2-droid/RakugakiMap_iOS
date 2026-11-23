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
        let imagery = app.buttons["map.imagery.toggle"]
        XCTAssertTrue(imagery.waitForExistence(timeout: 5))
        XCTAssertEqual(imagery.label, "航空写真に切り替え")
        imagery.tap()
        XCTAssertEqual(imagery.label, "標準地図に切り替え")
        imagery.tap()
        XCTAssertEqual(imagery.label, "航空写真に切り替え")

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

        XCTAssertTrue(screen(UI.photoDetailScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[UI.arButton].waitForExistence(timeout: 5))
    }

    /// 近くにARがあるときの地図。位置もサーバーも使わず、決まった表示（強さ3・右向きの矢印・見られる距離）を出して見た目を確かめる
    func testNearbyARSensorShowsMeterAndCameraButton() throws {
        let app = launchApp(extraArguments: ["--ar-sensor-ui-testing"])

        XCTAssertTrue(screen(UI.mapScreen, in: app).waitForExistence(timeout: 5))
        let sensor = screen("map.ar-sensor", in: app)
        XCTAssertTrue(sensor.waitForExistence(timeout: 5))
        XCTAssertEqual(sensor.label, "ARの気配")
        let open = app.buttons["map.ar-sensor.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertEqual(open.label, "カメラでさがす")

        // 見た目を後から目で確かめられるよう、画面写真をテスト結果に残す
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "地図の気配メーター"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// ふだんの地図には、気配メーターも「カメラでさがす」も出ない
    func testMapHidesARSensorWhenNothingIsNearby() throws {
        let app = launchApp()

        XCTAssertTrue(screen(UI.mapScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map.filter.all"].waitForExistence(timeout: 5))
        XCTAssertFalse(screen("map.ar-sensor", in: app).exists)
        XCTAssertFalse(app.buttons["map.ar-sensor.open"].exists)
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [UI.launchArgument] + extraArguments
        app.launch()
        // 起動直後は「今日」。地図のタブへ移ってから確かめる
        let mapTab = app.buttons["tab.map"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
        mapTab.tap()
        return app
    }

    private func screen(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
