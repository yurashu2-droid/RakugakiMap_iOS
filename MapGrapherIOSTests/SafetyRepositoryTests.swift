import Foundation
import MapGrapherCore
import XCTest
@testable import MapGrapherIOS

@MainActor
final class SafetyRepositoryTests: XCTestCase {
    func testReportUsesStableRequestAndDoesNotInferResolution() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = SafetyTestSession(context)
        let remote = SafetyTestRPC()
        let requestID = UUID()
        let targetID = UUID()
        let reportID = UUID()
        remote.responses["report_content"] = try json([[
            "report_id": reportID.uuidString,
            "received_at": "2026-09-21T00:00:00Z", "status": "RECEIVED"
        ]])
        let repository = SafetyRepository(remote: remote, session: session,
                                          invalidateAssets: { _ in })
        let receipt = try await repository.report(requestID: requestID, kind: .photo,
            targetID: targetID, reason: .privacy, detail: "位置が見える", context: context)
        XCTAssertEqual(receipt.id, reportID)
        XCTAssertEqual(receipt.status, "RECEIVED")
        XCTAssertEqual(remote.calls, ["report_content"])
        let payload = try XCTUnwrap(remote.parameters)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["client_request_id"] as? String, requestID.uuidString)
        XCTAssertEqual(object["target_kind"] as? String, "PHOTO")
        XCTAssertEqual(object["reason"] as? String, "PRIVACY")
    }

    func testBlockInvalidatesImagesOnlyAfterMatchingResponse() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let target = UUID()
        let remote = SafetyTestRPC()
        var invalidations = 0
        let repository = SafetyRepository(remote: remote, session: SafetyTestSession(context),
            invalidateAssets: { _ in invalidations += 1 })
        remote.responses["block_user"] = try json([[
            "blocked_user_id": UUID().uuidString, "blocked_at": "2026-09-21T00:00:00Z"
        ]])
        do {
            try await repository.block(userID: target, context: context)
            XCTFail("別利用者の応答を成功と扱ってはいけません")
        } catch { }
        XCTAssertEqual(invalidations, 0)
        remote.responses["block_user"] = try json([[
            "blocked_user_id": target.uuidString, "blocked_at": "2026-09-21T00:00:00Z"
        ]])
        try await repository.block(userID: target, context: context)
        XCTAssertEqual(invalidations, 1)
    }

    func testAccountSwitchDiscardsSafetyResponse() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = SafetyTestSession(context)
        let remote = SafetyTestRPC()
        remote.responses["list_blocked_users"] = try json([])
        remote.onCall = { await session.set(SessionContext(userID: UUID(), epoch: UUID())) }
        let repository = SafetyRepository(remote: remote, session: session,
                                          invalidateAssets: { _ in })
        do {
            _ = try await repository.blockedUsers(context: context)
            XCTFail("旧アカウントの結果を表示してはいけません")
        } catch let error as AppFailure {
            XCTAssertEqual(error, .cancelled)
        }
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
}

private actor SafetyTestSession: SessionProviding {
    var context: SessionContext?
    init(_ context: SessionContext) { self.context = context }
    func set(_ value: SessionContext?) { context = value }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ value: SessionContext) -> Bool { context == value }
}

@MainActor
private final class SafetyTestRPC: GroupRPCCalling {
    var responses: [String: Data] = [:]
    var calls: [String] = []
    var parameters: Data?
    var onCall: (@Sendable () async -> Void)?

    func call<Parameters: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, parameters: Parameters, as type: Result.Type
    ) async throws -> Result {
        calls.append(name)
        self.parameters = try SupabaseContract.encoder.encode(parameters)
        if let onCall { await onCall() }
        guard let data = responses[name] else { throw AppFailure.notFound }
        return try SupabaseContract.decoder.decode(type, from: data)
    }

    func callVoid<Parameters: Encodable & Sendable>(
        _ name: String, parameters: Parameters
    ) async throws {
        XCTFail("安全機能のRPCは確認可能な応答が必要です")
    }
}
