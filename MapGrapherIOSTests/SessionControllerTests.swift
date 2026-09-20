import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

@MainActor
final class SessionControllerTests: XCTestCase {
    func testLogoutInvalidatesOldContextEvenWhenRemoteLogoutFails() async throws {
        let user = UUID()
        let auth = FakeAuthService(snapshot: .authenticated(user), signOutFailure: true)
        let controller = SessionController(auth: auth)
        await controller.start()
        let restored = await controller.currentContext()
        let old = try XCTUnwrap(restored)

        do {
            try await controller.signOut()
            XCTFail("通信失敗を呼び出し元へ知らせる")
        } catch { }

        XCTAssertEqual(controller.state, .signedOut)
        let isOldCurrent = await controller.isCurrent(old)
        let afterLogout = await controller.currentContext()
        XCTAssertFalse(isOldCurrent)
        XCTAssertNil(afterLogout)
    }

    func testSwitchingAccountReplacesEpoch() async throws {
        let first = UUID()
        let second = UUID()
        let auth = FakeAuthService(snapshot: .authenticated(first))
        let controller = SessionController(auth: auth)
        await controller.start()
        let restored = await controller.currentContext()
        let old = try XCTUnwrap(restored)
        auth.nextSignInID = second
        try await controller.signIn(email: "test@example.invalid", password: "placeholder")
        let switched = await controller.currentContext()
        let isOldCurrent = await controller.isCurrent(old)
        XCTAssertEqual(switched?.userID, second)
        XCTAssertFalse(isOldCurrent)
    }

    func testConfirmationPendingDoesNotExposeSession() async throws {
        let auth = FakeAuthService(snapshot: .signedOut)
        let controller = SessionController(auth: auth)
        await controller.start()
        try await controller.signUp(email: "test@example.invalid", password: "placeholder", displayName: "試験")
        XCTAssertEqual(controller.state, .awaitingEmailConfirmation)
        let current = await controller.currentContext()
        XCTAssertNil(current)
    }

    func testExpiredRestorationRequiresReauthentication() async {
        let auth = FakeAuthService(snapshot: .reauthenticationRequired)
        let controller = SessionController(auth: auth)
        await controller.start()
        XCTAssertEqual(controller.state, .reauthenticationRequired)
    }

    func testLogoutDuringOldSessionInvalidationCannotRestoreNewAccount() async throws {
        let first = UUID()
        let auth = FakeAuthService(snapshot: .authenticated(first))
        let controller = SessionController(auth: auth)
        await controller.start()
        let gate = InvalidationGate()
        controller.onInvalidation = { _ in await gate.suspend() }
        auth.nextSignInID = UUID()

        let switching = Task {
            try await controller.signIn(email: "test@example.invalid", password: "placeholder")
        }
        await gate.waitUntilStarted()
        try await controller.signOut()
        gate.resume()
        try await switching.value

        XCTAssertEqual(controller.state, .signedOut)
        let current = await controller.currentContext()
        XCTAssertNil(current)
    }
}

@MainActor
private final class InvalidationGate {
    private var started: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func suspend() async {
        hasStarted = true
        started?.resume()
        started = nil
        await withCheckedContinuation { blocked = $0 }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { started = $0 }
    }

    func resume() {
        blocked?.resume()
        blocked = nil
    }
}

@MainActor
private final class FakeAuthService: AuthSessionServicing {
    var snapshot: AuthSessionState
    var nextSignInID = UUID()
    var signOutFailure: Bool
    let events = AsyncStream<AuthSessionState> { _ in }

    init(snapshot: AuthSessionState, signOutFailure: Bool = false) {
        self.snapshot = snapshot
        self.signOutFailure = signOutFailure
    }

    func restore() async -> AuthSessionState { snapshot }
    func signIn(email: String, password: String) async throws -> UUID { nextSignInID }
    func signUp(email: String, password: String, displayName: String) async throws -> UUID? { nil }
    func signOut() async throws {
        if signOutFailure { throw AppFailure.offline }
    }
    func requestPasswordReset(email: String) async throws { }
    func completeAuthURL(_ url: URL) async throws -> UUID { nextSignInID }
}
