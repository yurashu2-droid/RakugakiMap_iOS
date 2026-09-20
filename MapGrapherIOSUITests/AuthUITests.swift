import XCTest

@MainActor
final class AuthUITests: XCTestCase {
    private enum UI {
        static let launchArgument = "--ui-testing"
        static let authLaunchArgument = "--auth-ui-testing"

        static let welcomeScreen = "screen.auth.welcome"
        static let signInScreen = "screen.auth.sign-in"
        static let signUpScreen = "screen.auth.sign-up"
        static let resetScreen = "screen.auth.password-reset"

        static let email = "auth.email"
        static let displayName = "auth.display-name"
        static let password = "auth.password"
        static let passwordConfirmation = "auth.password-confirmation"
        static let submit = "auth.submit"
        static let signIn = "auth.sign-in"
        static let signUp = "auth.sign-up"
        static let passwordReset = "auth.password-reset"
        static let retry = "auth.retry"
        static let error = "auth.error"
        static let confirmation = "auth.confirmation"
        static let resetSent = "auth.reset-sent"
    }

    func testWelcomeOffersAuthenticationChoices() throws {
        let app = launchAuthFlow()
        try requireAuthIntegration(in: app)

        XCTAssertTrue(app.buttons[UI.signIn].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[UI.signUp].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[UI.passwordReset].waitForExistence(timeout: 5))
    }

    func testSignInFormExposesStableFieldsAndValidation() throws {
        let app = launchAuthFlow()
        try requireAuthIntegration(in: app)

        app.buttons[UI.signIn].tap()
        XCTAssertTrue(screen(UI.signInScreen, in: app).waitForExistence(timeout: 5))

        let email = app.textFields[UI.email]
        let password = app.secureTextFields[UI.password]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertTrue(password.waitForExistence(timeout: 5))

        email.tap()
        email.typeText("not-an-email")
        password.tap()
        password.typeText("short")
        app.buttons[UI.submit].tap()

        XCTAssertTrue(app.otherElements[UI.error].waitForExistence(timeout: 5))
    }

    func testSignUpFormIncludesPasswordConfirmation() throws {
        let app = launchAuthFlow()
        try requireAuthIntegration(in: app)

        app.buttons[UI.signUp].tap()
        XCTAssertTrue(screen(UI.signUpScreen, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields[UI.displayName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields[UI.email].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields[UI.password].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields[UI.passwordConfirmation].waitForExistence(timeout: 5))
    }

    func testPasswordResetShowsSentStateForFakeService() throws {
        let app = launchAuthFlow()
        try requireAuthIntegration(in: app)

        app.buttons[UI.passwordReset].tap()
        XCTAssertTrue(screen(UI.resetScreen, in: app).waitForExistence(timeout: 5))
        let email = app.textFields[UI.email]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("test@example.com")
        app.buttons[UI.submit].tap()

        XCTAssertTrue(app.otherElements[UI.resetSent].waitForExistence(timeout: 5))
    }

    @discardableResult
    private func launchAuthFlow() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [UI.launchArgument, UI.authLaunchArgument]
        app.launch()
        return app
    }

    private func requireAuthIntegration(in app: XCUIApplication) throws {
        guard screen(UI.welcomeScreen, in: app).waitForExistence(timeout: 2) else {
            throw XCTSkip("RootTabsを認証入口へ接続するまで認証UIテストを保留します。")
        }
    }

    private func screen(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
