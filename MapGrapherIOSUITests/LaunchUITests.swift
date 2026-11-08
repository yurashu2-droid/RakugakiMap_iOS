import XCTest

@MainActor
final class LaunchUITests: XCTestCase {
    private enum UI {
        static let launchArgument = "--ui-testing"

        static let todayScreen = "screen.today"
        static let mapScreen = "screen.map"
        static let groupsScreen = "screen.groups"
        static let notificationsScreen = "screen.notifications"
        static let profileScreen = "screen.profile"
        static let arPreviewScreen = "screen.ar-preview"

        static let arPreviewButton = "map.ar-preview.button"
    }

    private var app: XCUIApplication!

    func testLaunchesJapaneseShellWithFiveTabs() throws {
        launchApp()

        XCTAssertTrue(screen(UI.todayScreen).waitForExistence(timeout: 5))
        XCTAssertEqual(screen(UI.todayScreen).label, "今日")

        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab."))
        XCTAssertEqual(tabs.count, 5)
        assertTab("tab.today", label: "今日", selected: true)
        assertTab("tab.groups", label: "グループ")
        assertTab("tab.map", label: "地図")
        assertTab("tab.notifications", label: "お知らせ")
        assertTab("tab.profile", label: "マイページ")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "今日の画面（起動直後）"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSwitchesBetweenFiveTabs() throws {
        launchApp()

        tapTab("tab.groups", screen: UI.groupsScreen, screenLabel: "グループ")
        tapTab("tab.map", screen: UI.mapScreen, screenLabel: "地図")
        tapTab("tab.notifications", screen: UI.notificationsScreen, screenLabel: "お知らせ")
        tapTab("tab.profile", screen: UI.profileScreen, screenLabel: "マイページ")
        tapTab("tab.today", screen: UI.todayScreen, screenLabel: "今日")
    }

    func testTodayShortcutsOpenTheirTabs() throws {
        launchApp()

        let group = app.buttons["today.group"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.tap()
        XCTAssertTrue(screen(UI.groupsScreen).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.groups"].isSelected)

        tapTab("tab.today", screen: UI.todayScreen, screenLabel: "今日")
        let nearby = app.buttons["today.nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 5))
        nearby.tap()
        XCTAssertTrue(screen(UI.mapScreen).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.map"].isSelected)
    }

    func testTodayCameraOpensPostingFlow() throws {
        launchApp()

        let camera = app.buttons["today.mission.camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        camera.tap()
        XCTAssertTrue(screen("screen.posting.capture").waitForExistence(timeout: 5))
    }

    func testOpensARPrototypeFromMap() throws {
        launchApp()
        tapTab("tab.map", screen: UI.mapScreen, screenLabel: "地図")

        let arButton = app.buttons[UI.arPreviewButton]
        XCTAssertTrue(arButton.waitForExistence(timeout: 5))
        XCTAssertEqual(arButton.label, "AR動作確認")

        arButton.tap()

        let arScreen = screen(UI.arPreviewScreen)
        XCTAssertTrue(arScreen.waitForExistence(timeout: 5))
        XCTAssertEqual(arScreen.label, "AR試作")
    }

    @MainActor
    private func launchApp() {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [UI.launchArgument]
        app.launch()
    }

    private func screen(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func assertTab(_ identifier: String, label: String, selected: Bool = false) {
        let tab = app.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "タブが見つかりません: \(label)")
        XCTAssertEqual(tab.label, label)
        if selected {
            XCTAssertTrue(tab.isSelected, "選択中のタブではありません: \(label)")
        }
    }

    private func tapTab(_ identifier: String, screen screenIdentifier: String, screenLabel: String) {
        let tab = app.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "タブが見つかりません: \(identifier)")
        tab.tap()

        let destination = screen(screenIdentifier)
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, screenLabel)
        XCTAssertTrue(tab.isSelected, "選択中のタブではありません: \(identifier)")
    }
}
