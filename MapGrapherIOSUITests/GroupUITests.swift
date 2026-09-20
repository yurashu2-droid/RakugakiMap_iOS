import XCTest

@MainActor
final class GroupUITests: XCTestCase {
    private let groupID = "00000000-0000-4000-8000-000000000211"
    private let notificationID = "00000000-0000-4000-8000-000000000216"

    func testGroupDetailShowsMissionAndAnswerEntry() throws {
        let app = launchApp()
        app.tabBars.buttons["グループ"].tap()
        XCTAssertTrue(element("screen.groups", in: app).waitForExistence(timeout: 5))
        let row = element("group.row.\(groupID)", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element("screen.group-detail", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group.mission.answer"].exists)
    }

    func testCreatesFakeGroupWithoutClaimingServerSave() throws {
        let app = launchApp()
        app.tabBars.buttons["グループ"].tap()
        app.buttons["groups.create"].tap()
        XCTAssertTrue(element("screen.group-create", in: app).waitForExistence(timeout: 5))
        let name = app.textFields["groups.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("試験グループ")
        app.buttons["groups.create.save"].tap()
        XCTAssertTrue(app.staticTexts["試験グループ"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("groups.notice.fake", in: app).exists)
    }

    func testNotificationExplainsUnavailableInvitationTarget() throws {
        let app = launchApp()
        app.tabBars.buttons["お知らせ"].tap()
        XCTAssertTrue(element("screen.notifications", in: app).waitForExistence(timeout: 5))
        let row = element("notification.row.\(notificationID)", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element("notifications.target.unavailable", in: app)
            .waitForExistence(timeout: 5))
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
