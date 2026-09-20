import Foundation
import MapGrapherCore
import XCTest
@testable import MapGrapherIOS

@MainActor
final class GroupsServiceTests: XCTestCase {
    func testBlockedGroupIdentitiesDoNotBreakVisibleGroup() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let groupID = UUID()
        let remote = FakeGroupRPC()
        remote.responses["list_my_group_summaries"] = try json([[
            "group_id": groupID.uuidString, "group_name": NSNull(),
            "group_description": NSNull(), "owner_id": NSNull(),
            "is_owner": false, "member_count": 2,
            "mission_id": NSNull(), "mission_date": NSNull(),
            "mission_status": NSNull(), "prompt_text": NSNull(),
            "setter_id": NSNull(), "setter_name": NSNull(),
            "answered_count": 0, "participant_count": 0,
            "has_answered": false
        ]])
        remote.responses["get_group_members"] = try json([[
            "member_id": NSNull(), "display_name": NSNull(),
            "user_unique_id": NSNull(), "avatar_path": NSNull(),
            "role": "OWNER", "status": "ACTIVE", "rotation_order": 0,
            "joined_at": "2026-09-21T00:00:00Z", "answered_today": false,
            "is_today_setter": false
        ]])
        let service = SupabaseGroupsService(remote: remote, session: FakeGroupSession(context))
        let summaries = try await service.summaries(context: context)
        XCTAssertEqual(summaries.first?.memberCount, 2)
        XCTAssertNil(summaries.first?.ownerID)
        XCTAssertEqual(summaries.first?.name, "ブロック中のグループ")
        let members = try await service.members(groupID: groupID, context: context)
        XCTAssertTrue(members.isEmpty)
    }

    func testSummaryKeepsMissionDateAndNullableFields() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let remote = FakeGroupRPC()
        let groupID = UUID()
        remote.responses["list_my_group_summaries"] = try json([[
            "group_id": groupID.uuidString, "group_name": "お題会",
            "group_description": "", "owner_id": owner.uuidString,
            "is_owner": true, "member_count": 2,
            "mission_id": NSNull(), "mission_date": "2026-09-21",
            "mission_status": NSNull(), "prompt_text": NSNull(),
            "setter_id": NSNull(), "setter_name": NSNull(),
            "answered_count": 0, "participant_count": 0,
            "has_answered": false
        ]])
        let service = SupabaseGroupsService(remote: remote, session: FakeGroupSession(context))
        let summaries = try await service.summaries(context: context)
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.id, groupID)
        XCTAssertEqual(summary.missionDate, "2026-09-21")
        XCTAssertNil(summary.missionStatus)
        XCTAssertNil(summary.missionID)
        XCTAssertNil(summary.promptText)
        XCTAssertEqual(remote.calls, ["list_my_group_summaries"])
    }

    func testUnknownMissionStatusIsRejected() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let remote = FakeGroupRPC()
        let missionID = UUID()
        remote.responses["reassign_group_mission_setter"] = try json([
            "id": missionID.uuidString, "group_id": UUID().uuidString,
            "mission_date": "2026-09-21", "setter_id": NSNull(),
            "prompt_text": NSNull(), "status": "SURPRISE",
            "prompt_set_at": NSNull(), "closes_at": "2026-09-22T00:00:00Z",
            "created_at": "2026-09-21T00:00:00Z", "updated_at": "2026-09-21T00:00:00Z"
        ])
        let service = SupabaseGroupsService(remote: remote, session: FakeGroupSession(context))
        do {
            _ = try await service.reassignSetter(missionID: missionID, context: context)
            XCTFail("不明な状態を画面へ渡してはいけません")
        } catch { }
    }

    func testNotificationPayloadAndRecipientRemainTyped() async throws {
        let owner = UUID()
        let context = SessionContext(userID: owner, epoch: UUID())
        let remote = FakeGroupRPC()
        remote.responses["list_notifications"] = try json([[
            "id": UUID().uuidString, "recipient_id": owner.uuidString,
            "actor_id": NSNull(), "event_type": "GROUP_INVITATION",
            "group_id": NSNull(), "mission_id": NSNull(), "photo_id": NSNull(),
            "payload": ["count": 3, "flag": true, "extra": NSNull()],
            "read_at": NSNull(), "created_at": "2026-09-21T00:00:00Z"
        ]])
        let service = SupabaseGroupsService(remote: remote, session: FakeGroupSession(context))
        let notifications = try await service.notifications(limit: 20, before: nil,
                                                             context: context)
        let notification = try XCTUnwrap(notifications.first)
        XCTAssertEqual(notification.recipientID, owner)
        XCTAssertNil(notification.actorID)
        XCTAssertNil(notification.readAt)
        if case .some(.number(let number)) = notification.payload["count"] {
            XCTAssertEqual(number, 3)
        } else { XCTFail("jsonb数値を保持できません") }
    }

    func testEpochChangeDiscardsResponse() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeGroupSession(context)
        let remote = FakeGroupRPC()
        remote.responses["list_my_group_summaries"] = try json([])
        remote.onCall = { await session.set(SessionContext(userID: context.userID,
                                                            epoch: UUID())) }
        let service = SupabaseGroupsService(remote: remote, session: session)
        do {
            _ = try await service.summaries(context: context)
            XCTFail("旧epochの応答は破棄します")
        } catch let failure as AppFailure {
            XCTAssertEqual(failure, .cancelled)
        }
    }

    func testVoidFailureAndNonIdempotentNetworkFailureAreNotRetried() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let remote = FakeGroupRPC()
        let service = SupabaseGroupsService(remote: remote, session: FakeGroupSession(context))
        remote.voidFailure = GroupRPCError.invalidVoidResponse
        do {
            try await service.leave(groupID: UUID(), context: context)
            XCTFail("void応答異常を成功扱いにしてはいけません")
        } catch { }
        XCTAssertEqual(remote.calls, ["leave_group"])
        remote.callFailure = URLError(.networkConnectionLost)
        do {
            _ = try await service.invite(groupID: UUID(), userUniqueID: "friend-id",
                                         context: context)
            XCTFail("通信断は呼出元へ伝えます")
        } catch { }
        XCTAssertEqual(remote.calls, ["leave_group", "invite_group_member"])
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
}

private actor FakeGroupSession: SessionProviding {
    var context: SessionContext?
    init(_ context: SessionContext) { self.context = context }
    func set(_ context: SessionContext?) { self.context = context }
    func currentContext() -> SessionContext? { context }
    func isCurrent(_ context: SessionContext) -> Bool { self.context == context }
}

@MainActor
private final class FakeGroupRPC: GroupRPCCalling {
    var responses: [String: Data] = [:]
    var calls: [String] = []
    var onCall: (@Sendable () async -> Void)?
    var callFailure: Error?
    var voidFailure: Error?

    func call<Parameters: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, parameters: Parameters, as type: Result.Type
    ) async throws -> Result {
        calls.append(name)
        if let onCall { await onCall() }
        if let callFailure { throw callFailure }
        guard let data = responses[name] else { throw AppFailure.notFound }
        return try SupabaseContract.decoder.decode(Result.self, from: data)
    }

    func callVoid<Parameters: Encodable & Sendable>(
        _ name: String, parameters: Parameters
    ) async throws {
        calls.append(name)
        if let onCall { await onCall() }
        if let voidFailure { throw voidFailure }
    }
}
