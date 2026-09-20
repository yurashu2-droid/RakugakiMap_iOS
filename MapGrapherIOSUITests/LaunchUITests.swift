import XCTest

@MainActor
final class LaunchUITests: XCTestCase {
    private enum UI {
        static let launchArgument = "--ui-testing"

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

        XCTAssertEqual(app.tabBars.buttons.count, 4)
        assertTab(label: "地図", selected: true)
        assertTab(label: "グループ")
        assertTab(label: "お知らせ")
        assertTab(label: "マイページ")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "最小shell起動画面"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSwitchesBetweenFourTabs() throws {
        launchApp()

        tapTab(label: "グループ", screen: UI.groupsScreen, screenLabel: "グループ")
        tapTab(label: "お知らせ", screen: UI.notificationsScreen, screenLabel: "お知らせ")
        tapTab(label: "マイページ", screen: UI.profileScreen, screenLabel: "マイページ")
        tapTab(label: "地図", screen: UI.mapScreen, screenLabel: "地図")
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

    private func assertTab(label: String, selected: Bool = false) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "タブが見つかりません: \(label)")
        XCTAssertEqual(tab.label, label)
        if selected {
            XCTAssertTrue(tab.isSelected, "選択中のタブではありません: \(label)")
        }
    }

    private func tapTab(label: String, screen screenIdentifier: String, screenLabel: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "タブが見つかりません: \(label)")
        tab.tap()

        let destination = screen(screenIdentifier)
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, screenLabel)
        XCTAssertTrue(tab.isSelected, "選択中のタブではありません: \(label)")
    }
}
