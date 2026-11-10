import Foundation
import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

/// ログインまわりの失敗を、画面に出す理由へ正しく振り分けるか。
/// 2026-11-11、検証用Supabaseが止まっていたときに「処理に失敗しました」としか出なかったことへの対処。
final class AuthErrorMappingTests: XCTestCase {
    func testMissingHostIsReportedAsServerUnreachable() {
        XCTAssertEqual(SessionAuthUIAdapter.map(URLError(.cannotFindHost)), .serverUnreachable)
        XCTAssertEqual(SessionAuthUIAdapter.map(URLError(.dnsLookupFailed)), .serverUnreachable)
    }

    func testNoConnectionIsReportedAsOffline() {
        XCTAssertEqual(SessionAuthUIAdapter.map(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(SessionAuthUIAdapter.map(AppFailure.offline), .offline)
    }

    func testOtherNetworkFailuresAreServiceUnavailable() {
        XCTAssertEqual(SessionAuthUIAdapter.map(URLError(.timedOut)), .serviceUnavailable)
        XCTAssertEqual(SessionAuthUIAdapter.map(AppFailure.serviceUnavailable), .serviceUnavailable)
    }

    func testEmailLimitsAreRecognizedFromServerErrorCodes() {
        XCTAssertEqual(SessionAuthUIAdapter.map(ServerError(code: "over_email_send_rate_limit")), .emailRateLimited)
        XCTAssertEqual(SessionAuthUIAdapter.map(ServerError(code: "email_address_not_authorized")), .emailNotAllowed)
    }

    func testUnrecognizedErrorStaysUnknown() {
        XCTAssertEqual(SessionAuthUIAdapter.map(ServerError(code: "something_else")), .unknown)
    }

    /// Supabaseのエラーは、説明文にエラーコードを含む。その形だけをまねた合成のエラー
    private struct ServerError: Error {
        let code: String
    }
}
