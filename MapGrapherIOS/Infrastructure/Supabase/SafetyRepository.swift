import Foundation
import MapGrapherCore

@MainActor
protocol SafetyServing {
    func report(requestID: UUID, kind: SafetyTargetKind, targetID: UUID,
                reason: SafetyReportReason, detail: String,
                context: SessionContext) async throws -> SafetyReportReceipt
    func block(userID: UUID, context: SessionContext) async throws
    func unblock(userID: UUID, context: SessionContext) async throws
    func blockedUsers(context: SessionContext) async throws -> [BlockedUser]
}

/// B02の本人確認はサーバーのauth.uid()で行う。端末のcontextは応答混入防止に使う。
@MainActor
final class SafetyRepository: SafetyServing {
    private let remote: any GroupRPCCalling
    private let session: any SessionProviding
    private let invalidateAssets: @MainActor (SessionContext) async -> Void

    init(remote: any GroupRPCCalling, session: any SessionProviding,
         invalidateAssets: @escaping @MainActor (SessionContext) async -> Void) {
        self.remote = remote
        self.session = session
        self.invalidateAssets = invalidateAssets
    }

    func report(requestID: UUID, kind: SafetyTargetKind, targetID: UUID,
                reason: SafetyReportReason, detail: String,
                context: SessionContext) async throws -> SafetyReportReceipt {
        try await check(context)
        guard detail.count <= 500 else { throw AppFailure.validation("通報内容は500文字以内にしてください") }
        let rows: [SafetyReportDTO] = try await remote.call("report_content",
            parameters: SafetyReportRequestDTO(clientRequestId: requestID,
                targetKind: kind, targetId: targetID, reason: reason, detail: detail),
            as: [SafetyReportDTO].self)
        try await check(context)
        guard rows.count == 1, let row = rows.first,
              ["RECEIVED", "REVIEWING", "RESOLVED"].contains(row.status) else {
            throw AppFailure.serviceUnavailable
        }
        return SafetyReportReceipt(id: row.reportId, receivedAt: row.receivedAt,
                                   status: row.status)
    }

    func block(userID: UUID, context: SessionContext) async throws {
        try await check(context)
        guard userID != context.userID else { throw AppFailure.validation("自分自身はブロックできません") }
        let rows: [BlockUserDTO] = try await remote.call("block_user",
            parameters: SafetyUserRequestDTO(targetUserId: userID), as: [BlockUserDTO].self)
        try await check(context)
        guard rows.count == 1, rows[0].blockedUserId == userID else {
            throw AppFailure.serviceUnavailable
        }
        await invalidateAssets(context)
        try await check(context)
    }

    func unblock(userID: UUID, context: SessionContext) async throws {
        try await check(context)
        let rows: [UnblockUserDTO] = try await remote.call("unblock_user",
            parameters: SafetyUserRequestDTO(targetUserId: userID), as: [UnblockUserDTO].self)
        try await check(context)
        guard rows.count == 1, rows[0].unblockedUserId == userID,
              rows[0].unblocked else { throw AppFailure.serviceUnavailable }
        await invalidateAssets(context)
        try await check(context)
    }

    func blockedUsers(context: SessionContext) async throws -> [BlockedUser] {
        try await check(context)
        let rows: [BlockedUserDTO] = try await remote.call("list_blocked_users",
            parameters: SafetyEmptyRequestDTO(), as: [BlockedUserDTO].self)
        try await check(context)
        return rows.map { BlockedUser(id: $0.targetUserId, uniqueID: $0.userUniqueId,
                                      displayName: $0.displayName, blockedAt: $0.blockedAt) }
    }

    private func check(_ context: SessionContext) async throws {
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
    }
}

private struct SafetyEmptyRequestDTO: Encodable, Sendable {}
private struct SafetyUserRequestDTO: Encodable, Sendable { let targetUserId: UUID }
private struct SafetyReportRequestDTO: Encodable, Sendable {
    let clientRequestId: UUID
    let targetKind: SafetyTargetKind
    let targetId: UUID
    let reason: SafetyReportReason
    let detail: String
}
private struct SafetyReportDTO: Decodable, Sendable {
    let reportId: UUID
    let receivedAt: Date
    let status: String
}
private struct BlockUserDTO: Decodable, Sendable {
    let blockedUserId: UUID
    let blockedAt: Date
}
private struct UnblockUserDTO: Decodable, Sendable {
    let unblockedUserId: UUID
    let unblocked: Bool
}
private struct BlockedUserDTO: Decodable, Sendable {
    let targetUserId: UUID
    let userUniqueId: String
    let displayName: String
    let blockedAt: Date
}
