import XCTest

@MainActor
final class LaunchUITests: XCTestCase {
    private enum UI {
        static let launchArgument = "--ui-testing"

        static let mapTab = "tab.map"
        static let groupsTab = "tab.groups"
        static let notificationsTab = "tab.notifications"
        static let profileTab = "tab.profile"

        static let mapScreen = "screen.map"
        static let groupsScreen = "screen.groups"
        static let notificationsScreen = "screen.notifications"
        static let profileScreen = "screen.profile"
        static let arPreviewScreen = "screen.ar-preview"

        static let arPreviewButton = "map.ar-preview.button"
    }

    private var app: XCUIApplication!

    func testLaunchesJapaneseShellWithFourTabs() throws {
        launchApp()

        XCTAssertTrue(screen(UI.mapScreen).waitForExistence(timeout: 5))
        XCTAssertEqual(screen(UI.mapScreen).label, "地図")

        assertTab(UI.mapTab, label: "地図", selected: true)
        assertTab(UI.groupsTab, label: "グループ")
        assertTab(UI.notificationsTab, label: "お知らせ")
        assertTab(UI.profileTab, label: "マイページ")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "最小shell起動画面"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSwitchesBetweenFourTabs() throws {
        launchApp()

        tapTab(UI.groupsTab, screen: UI.groupsScreen, label: "グループ")
        tapTab(UI.notificationsTab, screen: UI.notificationsScreen, label: "お知らせ")
        tapTab(UI.profileTab, screen: UI.profileScreen, label: "マイページ")
        tapTab(UI.mapTab, screen: UI.mapScreen, label: "地図")
    }

    func testOpensARPrototypeFromMap() throws {
        launchApp()

        XCTAssertTrue(screen(UI.mapScreen).waitForExistence(timeout: 5))

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

    private func assertTab(
        _ identifier: String,
        label: String,
        selected: Bool = false
    ) {
        let tab = app.tabBars.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "タブが見つかりません: \(identifier)")
        XCTAssertEqual(tab.label, label)
        if selected {
            XCTAssertTrue(tab.isSelected, "選択中のタブではありません: \(identifier)")
        }
    }

    private func tapTab(_ identifier: String, screen screenIdentifier: String, label: String) {
        let tab = app.tabBars.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "タブが見つかりません: \(identifier)")
        tab.tap()

        let destination = screen(screenIdentifier)
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, label)
        XCTAssertTrue(tab.isSelected, "選択中のタブではありません: \(identifier)")
    }
}
