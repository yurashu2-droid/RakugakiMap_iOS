import Foundation
import MapGrapherCore

/// 書込RPCは1操作につき1回だけ呼ぶ。通信断後は画面で状態を再取得する。
@MainActor
final class SupabaseGroupsService: GroupsServing {
    private let remote: any GroupRPCCalling
    private let session: any SessionProviding

    init(remote: any GroupRPCCalling, session: any SessionProviding) {
        self.remote = remote; self.session = session
    }

    convenience init(gateway: SupabaseGateway, session: any SessionProviding) {
        self.init(remote: gateway, session: session)
    }

    func createGroup(requestID: UUID, name: String, description: String,
                     context: SessionContext) async throws -> GroupRecord {
        let row: GroupRowDTO = try await call("create_group",
            parameters: CreateGroupRequestDTO(clientRequestId: requestID,
                                              groupName: name, groupDescription: description),
            context: context)
        guard row.ownerId == context.userID, row.clientRequestId == requestID else {
            throw AppFailure.validation("グループ作成の応答が一致しません")
        }
        return GroupMapper.group(row)
    }

    func updateGroup(id: UUID, name: String, description: String,
                     context: SessionContext) async throws -> GroupRecord {
        let row: GroupRowDTO = try await call("update_group",
            parameters: UpdateGroupRequestDTO(targetGroupId: id,
                groupName: name, groupDescription: description), context: context)
        guard row.id == id else { throw AppFailure.validation("グループ更新の応答が一致しません") }
        return GroupMapper.group(row)
    }

    func summaries(context: SessionContext) async throws -> [GroupSummary] {
        let rows: [GroupSummaryDTO] = try await call("list_my_group_summaries",
            parameters: EmptyRPCRequestDTO(), context: context)
        return try rows.map(GroupMapper.summary)
    }

    func members(groupID: UUID, context: SessionContext) async throws -> [GroupMember] {
        let rows: [GroupMemberDTO] = try await call("get_group_members",
            parameters: GroupIDRequestDTO(targetGroupId: groupID), context: context)
        return try rows.map(GroupMapper.member)
    }

    func invite(groupID: UUID, userUniqueID: String,
                context: SessionContext) async throws -> GroupInvitation {
        let row: GroupInvitationRowDTO = try await call("invite_group_member",
            parameters: InviteGroupMemberRequestDTO(targetGroupId: groupID,
                targetUserUniqueId: userUniqueID), context: context)
        guard row.groupId == groupID else { throw AppFailure.validation("招待先グループが不正です") }
        return try GroupMapper.invitation(row)
    }

    func cancelInvitation(id: UUID, context: SessionContext) async throws -> GroupInvitation {
        let row: GroupInvitationRowDTO = try await call("cancel_group_invitation",
            parameters: InvitationIDRequestDTO(targetInvitationId: id), context: context)
        guard row.id == id else { throw AppFailure.validation("招待取消の応答が一致しません") }
        return try GroupMapper.invitation(row)
    }

    func invitations(context: SessionContext) async throws -> [GroupInvitationSummary] {
        let rows: [GroupInvitationSummaryDTO] = try await call("list_my_group_invitations",
            parameters: EmptyRPCRequestDTO(), context: context)
        return try rows.map(GroupMapper.invitationSummary)
    }

    func respondInvitation(id: UUID, accepted: Bool,
                           context: SessionContext) async throws -> GroupInvitation {
        let row: GroupInvitationRowDTO = try await call("respond_group_invitation",
            parameters: RespondGroupInvitationRequestDTO(targetInvitationId: id,
                                                           accepted: accepted), context: context)
        guard row.id == id else { throw AppFailure.validation("招待回答の応答が一致しません") }
        return try GroupMapper.invitation(row)
    }

    func leave(groupID: UUID, context: SessionContext) async throws {
        try await void("leave_group", parameters: GroupIDRequestDTO(targetGroupId: groupID),
                       context: context)
    }

    func removeMember(groupID: UUID, memberID: UUID, context: SessionContext) async throws {
        try await void("remove_group_member",
            parameters: RemoveGroupMemberRequestDTO(targetGroupId: groupID,
                                                      targetMemberId: memberID), context: context)
    }

    func transferOwnership(groupID: UUID, newOwnerID: UUID,
                           context: SessionContext) async throws -> GroupRecord {
        let row: GroupRowDTO = try await call("transfer_group_ownership",
            parameters: TransferGroupOwnershipRequestDTO(targetGroupId: groupID,
                targetNewOwnerId: newOwnerID), context: context)
        guard row.id == groupID, row.ownerId == newOwnerID else {
            throw AppFailure.validation("所有権移譲の応答が一致しません")
        }
        return GroupMapper.group(row)
    }

    func archive(groupID: UUID, context: SessionContext) async throws -> GroupRecord {
        let row: GroupRowDTO = try await call("archive_group",
            parameters: GroupIDRequestDTO(targetGroupId: groupID), context: context)
        guard row.id == groupID, row.archivedAt != nil else {
            throw AppFailure.validation("アーカイブの応答が不正です")
        }
        return GroupMapper.group(row)
    }

    func reassignSetter(missionID: UUID, context: SessionContext) async throws -> GroupMission {
        let row: GroupMissionRowDTO = try await call("reassign_group_mission_setter",
            parameters: MissionIDRequestDTO(targetMissionId: missionID), context: context)
        guard row.id == missionID else { throw AppFailure.validation("担当変更の応答が不正です") }
        return try GroupMapper.mission(row)
    }

    func setPrompt(missionID: UUID, text: String,
                   context: SessionContext) async throws -> GroupMission {
        let row: GroupMissionRowDTO = try await call("set_group_mission_prompt",
            parameters: SetGroupMissionPromptRequestDTO(targetMissionId: missionID,
                targetPromptText: text), context: context)
        guard row.id == missionID else { throw AppFailure.validation("お題設定の応答が不正です") }
        return try GroupMapper.mission(row)
    }

    func missionStatus(groupID: UUID, context: SessionContext) async throws -> [GroupMissionParticipant] {
        let rows: [GroupMissionParticipantDTO] = try await call("get_group_mission_status",
            parameters: GroupIDRequestDTO(targetGroupId: groupID), context: context)
        guard rows.allSatisfy({ $0.groupId == groupID }) else {
            throw AppFailure.validation("お題状態のグループが一致しません")
        }
        return try rows.map(GroupMapper.participant)
    }

    func submitAnswer(missionID: UUID, photoID: UUID,
                      context: SessionContext) async throws -> GroupAnswer {
        let row: GroupAnswerRowDTO = try await call("submit_group_answer",
            parameters: SubmitGroupAnswerRequestDTO(targetMissionId: missionID,
                targetPhotoId: photoID), context: context)
        guard row.missionId == missionID, row.photoId == photoID,
              row.userId == context.userID else {
            throw AppFailure.validation("お題回答の応答が一致しません")
        }
        return GroupMapper.answer(row)
    }

    func withdrawAnswer(missionID: UUID, context: SessionContext) async throws {
        try await void("withdraw_group_answer",
            parameters: MissionIDRequestDTO(targetMissionId: missionID), context: context)
    }

    func notifications(limit: Int, before: String?,
                       context: SessionContext) async throws -> [GroupNotification] {
        guard (1...50).contains(limit) else { throw AppFailure.validation("通知件数が不正です") }
        let rows: [NotificationDTO] = try await call("list_notifications",
            parameters: ListNotificationsRequestDTO(targetLimit: limit,
                                                      targetBefore: before), context: context)
        guard rows.allSatisfy({ $0.recipientId == context.userID }) else {
            throw AppFailure.validation("通知の受信者が一致しません")
        }
        return rows.map(GroupMapper.notification)
    }

    func markNotificationRead(id: UUID, context: SessionContext) async throws -> GroupNotification {
        let row: NotificationDTO = try await call("mark_notification_read",
            parameters: NotificationIDRequestDTO(targetNotificationId: id), context: context)
        guard row.id == id, row.recipientId == context.userID else {
            throw AppFailure.validation("通知の応答が一致しません")
        }
        return GroupMapper.notification(row)
    }

    private func call<Parameters: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, parameters: Parameters, context: SessionContext
    ) async throws -> Result {
        try await check(context)
        let result = try await remote.call(name, parameters: parameters, as: Result.self)
        try await check(context)
        return result
    }

    private func void<Parameters: Encodable & Sendable>(
        _ name: String, parameters: Parameters, context: SessionContext
    ) async throws {
        try await check(context)
        try await remote.callVoid(name, parameters: parameters)
        try await check(context)
    }

    private func check(_ context: SessionContext) async throws {
        try Task.checkCancellation()
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
    }
}
