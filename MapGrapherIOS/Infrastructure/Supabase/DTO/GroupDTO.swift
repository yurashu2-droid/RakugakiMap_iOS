import Foundation

struct EmptyRPCRequestDTO: Encodable, Sendable { }
struct CreateGroupRequestDTO: Encodable, Sendable {
    let clientRequestId: UUID
    let groupName: String
    let groupDescription: String
}
struct UpdateGroupRequestDTO: Encodable, Sendable {
    let targetGroupId: UUID
    let groupName: String
    let groupDescription: String
}
struct GroupIDRequestDTO: Encodable, Sendable { let targetGroupId: UUID }
struct InvitationIDRequestDTO: Encodable, Sendable { let targetInvitationId: UUID }
struct MissionIDRequestDTO: Encodable, Sendable { let targetMissionId: UUID }
struct InviteGroupMemberRequestDTO: Encodable, Sendable {
    let targetGroupId: UUID
    let targetUserUniqueId: String
}
struct RespondGroupInvitationRequestDTO: Encodable, Sendable {
    let targetInvitationId: UUID
    let accepted: Bool
}
struct RemoveGroupMemberRequestDTO: Encodable, Sendable {
    let targetGroupId: UUID
    let targetMemberId: UUID
}
struct TransferGroupOwnershipRequestDTO: Encodable, Sendable {
    let targetGroupId: UUID
    let targetNewOwnerId: UUID
}
struct SetGroupMissionPromptRequestDTO: Encodable, Sendable {
    let targetMissionId: UUID
    let targetPromptText: String
}
struct SubmitGroupAnswerRequestDTO: Encodable, Sendable {
    let targetMissionId: UUID
    let targetPhotoId: UUID
}

struct GroupRowDTO: Decodable, Sendable {
    let id: UUID
    let ownerId: UUID
    let clientRequestId: UUID
    let name: String
    let description: String
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}
struct GroupSummaryDTO: Decodable, Sendable {
    let groupId: UUID
    let groupName: String?
    let groupDescription: String?
    let ownerId: UUID?
    let isOwner: Bool
    let memberCount: Int64
    let missionId: UUID?
    let missionDate: String?
    let missionStatus: String?
    let promptText: String?
    let setterId: UUID?
    let setterName: String?
    let answeredCount: Int64
    let participantCount: Int64
    let hasAnswered: Bool
}
struct GroupMemberDTO: Decodable, Sendable {
    let memberId: UUID?
    let displayName: String?
    let userUniqueId: String?
    let avatarPath: String?
    let role: String
    let status: String
    let rotationOrder: Int
    let joinedAt: Date
    let answeredToday: Bool
    let isTodaySetter: Bool
}
struct GroupInvitationRowDTO: Decodable, Sendable {
    let id: UUID
    let groupId: UUID
    let inviterId: UUID
    let inviteeId: UUID
    let status: String
    let expiresAt: Date
    let respondedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}
struct GroupInvitationSummaryDTO: Decodable, Sendable {
    let invitationId: UUID
    let groupId: UUID
    let groupName: String
    let inviterId: UUID
    let inviterName: String
    let memberCount: Int64
    let expiresAt: Date
    let createdAt: Date
}
struct GroupMissionRowDTO: Decodable, Sendable {
    let id: UUID
    let groupId: UUID
    let missionDate: String
    let setterId: UUID?
    let promptText: String?
    let status: String
    let promptSetAt: Date?
    let closesAt: Date
    let createdAt: Date
    let updatedAt: Date
}
struct GroupMissionParticipantDTO: Decodable, Sendable {
    let missionId: UUID
    let groupId: UUID
    let missionDate: String
    let missionStatus: String
    let promptText: String?
    let setterId: UUID?
    let participantId: UUID?
    let participantName: String?
    let participantAvatarPath: String?
    let rotationOrderSnapshot: Int
    let participantIsActive: Bool
    let answered: Bool
    let answerId: UUID?
    let answerPhotoId: UUID?
    let answerCreatedAt: Date?
    let photoAssetPath: String?
    let latestApprovedRakugakiAssetPath: String?
}
struct GroupAnswerRowDTO: Decodable, Sendable {
    let id: UUID
    let missionId: UUID
    let userId: UUID
    let photoId: UUID
    let createdAt: Date
    let updatedAt: Date
}
