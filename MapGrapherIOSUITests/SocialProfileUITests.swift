import XCTest

@MainActor
final class SocialProfileUITests: XCTestCase {
    private enum UI {
        static let launchArgument = "--ui-testing"
        static let profileTab = "マイページ"
        static let profileScreen = "screen.profile"
        static let profileEditScreen = "screen.profile.edit"
        static let friendsScreen = "screen.friends"
        static let requestsScreen = "screen.friend-requests"
        static let historyScreen = "screen.rakugaki-history"
        static let approvalScreen = "screen.rakugaki-approval"
        static let albumsScreen = "screen.albums"
        static let albumCreateScreen = "screen.album.create"
        static let albumDetailScreen = "screen.album-detail"
    }

    func testProfileNavigatesToFriendsAndRequests() throws {
        let app = launchProfile()

        app.buttons["profile.friends"].tap()
        XCTAssertTrue(screen(UI.friendsScreen, in: app).waitForExistence(timeout: 5))

        app.buttons["friends.pending"].tap()
        XCTAssertTrue(screen(UI.requestsScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "friend-request.accept.")
        ).firstMatch.waitForExistence(timeout: 5))
    }

    func testFriendRequestCanBeAcceptedInFakeModeWithoutClaimingNetworkSuccess() throws {
        let app = launchProfile()

        app.buttons["profile.friend-requests"].tap()
        XCTAssertTrue(screen(UI.requestsScreen, in: app).waitForExistence(timeout: 5))

        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "friend-request.accept.")
        ).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["social.notice.fake"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["social.operation.success"].exists)
    }

    func testProfileNameEditShowsPrototypeNotice() throws {
        let app = launchProfile()

        app.buttons["profile.edit"].tap()
        XCTAssertTrue(screen(UI.profileEditScreen, in: app).waitForExistence(timeout: 5))
        let name = app.textFields["profile.edit.display-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("新しい表示名")
        app.buttons["profile.edit.save"].tap()

        XCTAssertTrue(app.staticTexts["social.notice.fake"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["social.operation.success"].exists)
    }

    func testHistoryCanOpenApprovalAndAlbumFlowIsReachable() throws {
        let app = launchProfile()

        app.buttons["profile.history"].tap()
        XCTAssertTrue(screen(UI.historyScreen, in: app).waitForExistence(timeout: 5))
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "history.row.")
        ).firstMatch.tap()
        XCTAssertTrue(screen(UI.approvalScreen, in: app).waitForExistence(timeout: 5))
        app.buttons["history.approve"].tap()
        XCTAssertTrue(app.staticTexts["social.notice.fake"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["profile.albums"].tap()
        XCTAssertTrue(screen(UI.albumsScreen, in: app).waitForExistence(timeout: 5))
        app.buttons["album.create"].tap()
        XCTAssertTrue(screen(UI.albumCreateScreen, in: app).waitForExistence(timeout: 5))
        let title = app.textFields["album.create.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("旅の写真")
        app.buttons["album.create.save"].tap()
        XCTAssertTrue(screen(UI.albumsScreen, in: app).waitForExistence(timeout: 5))
        let album = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "album.row.")
        ).firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 5))
        album.tap()
        XCTAssertTrue(screen(UI.albumDetailScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["social.notice.fake"].waitForExistence(timeout: 5))
    }

    func testAlbumCanAddPhotoThroughInjectedServiceBoundary() throws {
        let app = launchProfile()

        app.buttons["profile.albums"].tap()
        XCTAssertTrue(screen(UI.albumsScreen, in: app).waitForExistence(timeout: 5))
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "album.row.")
        ).firstMatch.tap()
        XCTAssertTrue(screen(UI.albumDetailScreen, in: app).waitForExistence(timeout: 5))

        let photoID = app.textFields["album.photo-id"]
        XCTAssertTrue(photoID.waitForExistence(timeout: 5))
        photoID.tap()
        photoID.typeText("00000000-0000-4000-8000-000000000132")
        app.buttons["album.add-photo"].tap()
        XCTAssertTrue(app.staticTexts["social.notice.fake"].waitForExistence(timeout: 5))
    }

    private func launchProfile() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [UI.launchArgument]
        app.launch()

        let profileTab = app.tabBars.buttons[UI.profileTab]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(screen(UI.profileScreen, in: app).waitForExistence(timeout: 5))
        return app
    }

    private func screen(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
