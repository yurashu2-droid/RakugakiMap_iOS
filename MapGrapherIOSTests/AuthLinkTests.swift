import XCTest
@testable import MapGrapherIOS

final class AuthLinkTests: XCTestCase {
    private let callback = URL(string: "rakugakimap-dev://auth/callback")!

    func testOnlyExactRedirectAndKnownFlowAreAccepted() {
        let handler = AuthLinkHandler(redirectURL: callback)
        XCTAssertEqual(handler.flow(for: URL(string: "rakugakimap-dev://auth/callback?code=synthetic")!), .code)
        XCTAssertNil(handler.flow(for: URL(string: "rakugakimap-dev://evil/callback?code=synthetic")!))
        XCTAssertNil(handler.flow(for: URL(string: "rakugakimap-dev://auth/callback/extra?code=synthetic")!))
        XCTAssertNil(handler.flow(for: URL(string: "rakugakimap-dev://auth/callback?access_token=synthetic")!))
        XCTAssertNil(handler.flow(for: URL(string: "https://example.invalid/auth/callback?code=synthetic")!))
    }

    func testRejectsDuplicateOrMissingCode() {
        let handler = AuthLinkHandler(redirectURL: callback)
        XCTAssertNil(handler.flow(for: URL(string: "rakugakimap-dev://auth/callback?code=a&code=b")!))
        XCTAssertNil(handler.flow(for: URL(string: "rakugakimap-dev://auth/callback?code=")!))
    }
}
