import Foundation
import MapGrapherCore

/// UIはDTOやHTTPを扱わず、DBの権限判定後の値だけを受け取る。
@MainActor
protocol GroupsServing {
    func createGroup(requestID: UUID, name: String, description: String,
                     context: SessionContext) async throws -> GroupRecord
    func updateGroup(id: UUID, name: String, description: String,
                     context: SessionContext) async throws -> GroupRecord
    func summaries(context: SessionContext) async throws -> [GroupSummary]
    func members(groupID: UUID, context: SessionContext) async throws -> [GroupMember]
    func invite(groupID: UUID, userUniqueID: String,
                context: SessionContext) async throws -> GroupInvitation
    func cancelInvitation(id: UUID, context: SessionContext) async throws -> GroupInvitation
    func invitations(context: SessionContext) async throws -> [GroupInvitationSummary]
    func respondInvitation(id: UUID, accepted: Bool,
                           context: SessionContext) async throws -> GroupInvitation
    func leave(groupID: UUID, context: SessionContext) async throws
    func removeMember(groupID: UUID, memberID: UUID, context: SessionContext) async throws
    func transferOwnership(groupID: UUID, newOwnerID: UUID,
                           context: SessionContext) async throws -> GroupRecord
    func archive(groupID: UUID, context: SessionContext) async throws -> GroupRecord
    func reassignSetter(missionID: UUID, context: SessionContext) async throws -> GroupMission
    func setPrompt(missionID: UUID, text: String,
                   context: SessionContext) async throws -> GroupMission
    func missionStatus(groupID: UUID, context: SessionContext) async throws -> [GroupMissionParticipant]
    func submitAnswer(missionID: UUID, photoID: UUID,
                      context: SessionContext) async throws -> GroupAnswer
    func withdrawAnswer(missionID: UUID, context: SessionContext) async throws
    func notifications(limit: Int, before: String?,
                       context: SessionContext) async throws -> [GroupNotification]
    func markNotificationRead(id: UUID, context: SessionContext) async throws -> GroupNotification
}
