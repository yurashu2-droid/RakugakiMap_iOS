import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

@MainActor
final class ProfileBootstrapModelTests: XCTestCase {
    func testMissingProfileRequiresSetupBeforeAppCanOpen() async {
        let session = SessionController(auth: BootstrapAuthService())
        await session.start()
        let restored = await session.currentContext()
        let context = try! XCTUnwrap(restored)
        let service = BootstrapProfileService(exists: false)
        let model = ProfileBootstrapModel(context: context, session: session, service: service)

        await model.load()
        XCTAssertEqual(model.state, .needsProfile)
        XCTAssertFalse(model.canOpenApp)

        await model.submit(displayName: "試験者", uniqueID: "tester_01")
        XCTAssertEqual(model.state, .ready)
        XCTAssertTrue(model.canOpenApp)
        XCTAssertEqual(service.createdID, "tester_01")
    }
}

@MainActor
private final class BootstrapProfileService: ProfileBootstrapServing {
    let exists: Bool
    var createdID: String?
    init(exists: Bool) { self.exists = exists }
    func profileExists(context: SessionContext) async throws -> Bool { exists }
    func createProfile(context: SessionContext, displayName: String, uniqueID: String) async throws {
        createdID = uniqueID
    }
}

@MainActor
private final class BootstrapAuthService: AuthSessionServicing {
    private let user = UUID()
    let events = AsyncStream<AuthSessionState> { _ in }
    func restore() async -> AuthSessionState { .authenticated(user) }
    func signIn(email: String, password: String) async throws -> UUID { user }
    func signUp(email: String, password: String, displayName: String) async throws -> UUID? { user }
    func signOut() async throws { }
    func requestPasswordReset(email: String) async throws { }
    func completeAuthURL(_ url: URL) async throws -> UUID { user }
}
