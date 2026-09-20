import Foundation
import MapGrapherCore

enum GroupRole: String, Sendable { case owner = "OWNER", member = "MEMBER" }
enum GroupMemberStatus: String, Sendable { case active = "ACTIVE", left = "LEFT", removed = "REMOVED" }
enum GroupInvitationStatus: String, Sendable {
    case pending = "PENDING", accepted = "ACCEPTED", declined = "DECLINED"
    case canceled = "CANCELED", expired = "EXPIRED"
}
enum GroupMissionStatus: String, Sendable {
    case awaitingPrompt = "AWAITING_PROMPT", open = "OPEN", closed = "CLOSED"
}

struct GroupRecord: Sendable {
    let id: UUID
    let ownerID: UUID
    let clientRequestID: UUID
    let name: String
    let description: String
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct GroupSummary: Sendable {
    let id: UUID
    let name: String
    let description: String
    let ownerID: UUID?
    let isOwner: Bool
    let memberCount: Int64
    let missionID: UUID?
    /// DBがJSTで決めた日付。端末のタイムゾーンでDateへ変換しない。
    let missionDate: String?
    let missionStatus: GroupMissionStatus?
    let promptText: String?
    let setterID: UUID?
    let setterName: String?
    let answeredCount: Int64
    let participantCount: Int64
    let hasAnswered: Bool
}

struct GroupMember: Sendable {
    let id: UUID
    let displayName: String
    let userUniqueID: String
    let avatar: AssetReference?
    let role: GroupRole
    let status: GroupMemberStatus
    let rotationOrder: Int
    let joinedAt: Date
    let answeredToday: Bool
    let isTodaySetter: Bool
}

struct GroupInvitation: Sendable {
    let id: UUID
    let groupID: UUID
    let inviterID: UUID
    let inviteeID: UUID
    let status: GroupInvitationStatus
    let expiresAt: Date
    let respondedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct GroupInvitationSummary: Sendable {
    let id: UUID
    let groupID: UUID
    let groupName: String
    let inviterID: UUID
    let inviterName: String
    let memberCount: Int64
    let expiresAt: Date
    let createdAt: Date
}

struct GroupMission: Sendable {
    let id: UUID
    let groupID: UUID
    let missionDate: String
    let setterID: UUID?
    let promptText: String?
    let status: GroupMissionStatus
    let promptSetAt: Date?
    let closesAt: Date
    let createdAt: Date
    let updatedAt: Date
}

struct GroupMissionParticipant: Sendable {
    let missionID: UUID
    let groupID: UUID
    let missionDate: String
    let missionStatus: GroupMissionStatus
    let promptText: String?
    let setterID: UUID?
    let participantID: UUID
    let participantName: String
    let participantAvatar: AssetReference?
    let rotationOrderSnapshot: Int
    let isActive: Bool
    let answered: Bool
    let answerID: UUID?
    let answerPhotoID: UUID?
    let answerCreatedAt: Date?
    let photoAsset: AssetReference?
    let latestApprovedRakugakiAsset: AssetReference?
}

struct GroupAnswer: Sendable {
    let id: UUID
    let missionID: UUID
    let userID: UUID
    let photoID: UUID
    let createdAt: Date
    let updatedAt: Date
}

struct GroupNotification: Sendable {
    let id: UUID
    let recipientID: UUID
    let actorID: UUID?
    let eventType: String
    let groupID: UUID?
    let missionID: UUID?
    let photoID: UUID?
    let payload: [String: JSONValue]
    let readAt: Date?
    let createdAt: Date
}

enum GroupMapper {
    static func group(_ row: GroupRowDTO) -> GroupRecord {
        GroupRecord(id: row.id, ownerID: row.ownerId,
            clientRequestID: row.clientRequestId, name: row.name,
            description: row.description, archivedAt: row.archivedAt,
            createdAt: row.createdAt, updatedAt: row.updatedAt)
    }

    static func summary(_ row: GroupSummaryDTO) throws -> GroupSummary {
        let status = try row.missionStatus.map { try missionStatus($0) }
        if let date = row.missionDate { try validateMissionDate(date) }
        guard row.memberCount >= 0, row.answeredCount >= 0,
              row.participantCount >= 0 else { throw AppFailure.validation("グループ集計が不正です") }
        return GroupSummary(id: row.groupId, name: row.groupName ?? "ブロック中のグループ",
            description: row.groupDescription ?? "", ownerID: row.ownerId,
            isOwner: row.isOwner, memberCount: row.memberCount,
            missionID: row.missionId, missionDate: row.missionDate,
            missionStatus: status, promptText: row.promptText,
            setterID: row.setterId, setterName: row.setterName,
            answeredCount: row.answeredCount, participantCount: row.participantCount,
            hasAnswered: row.hasAnswered)
    }

    static func member(_ row: GroupMemberDTO) throws -> GroupMember? {
        if row.memberId == nil && row.displayName == nil && row.userUniqueId == nil {
            return nil
        }
        guard let id = row.memberId, let name = row.displayName,
              let uniqueID = row.userUniqueId else {
            throw AppFailure.validation("グループ参加者の情報が不正です")
        }
        guard let role = GroupRole(rawValue: row.role),
              let status = GroupMemberStatus(rawValue: row.status),
              (0...7).contains(row.rotationOrder) else {
            throw AppFailure.validation("グループ参加状態が不正です")
        }
        return GroupMember(id: id, displayName: name,
            userUniqueID: uniqueID,
            avatar: try asset(bucket: "avatars", path: row.avatarPath),
            role: role, status: status, rotationOrder: row.rotationOrder,
            joinedAt: row.joinedAt, answeredToday: row.answeredToday,
            isTodaySetter: row.isTodaySetter)
    }

    static func invitation(_ row: GroupInvitationRowDTO) throws -> GroupInvitation {
        guard let status = GroupInvitationStatus(rawValue: row.status) else {
            throw AppFailure.validation("招待状態が不正です")
        }
        return GroupInvitation(id: row.id, groupID: row.groupId,
            inviterID: row.inviterId, inviteeID: row.inviteeId, status: status,
            expiresAt: row.expiresAt, respondedAt: row.respondedAt,
            createdAt: row.createdAt, updatedAt: row.updatedAt)
    }

    static func invitationSummary(_ row: GroupInvitationSummaryDTO) throws -> GroupInvitationSummary {
        guard row.memberCount >= 0 else { throw AppFailure.validation("招待の参加者数が不正です") }
        return GroupInvitationSummary(id: row.invitationId, groupID: row.groupId,
            groupName: row.groupName, inviterID: row.inviterId,
            inviterName: row.inviterName, memberCount: row.memberCount,
            expiresAt: row.expiresAt, createdAt: row.createdAt)
    }

    static func mission(_ row: GroupMissionRowDTO) throws -> GroupMission {
        try validateMissionDate(row.missionDate)
        return GroupMission(id: row.id, groupID: row.groupId,
            missionDate: row.missionDate, setterID: row.setterId,
            promptText: row.promptText, status: try missionStatus(row.status),
            promptSetAt: row.promptSetAt, closesAt: row.closesAt,
            createdAt: row.createdAt, updatedAt: row.updatedAt)
    }

    static func participant(_ row: GroupMissionParticipantDTO) throws -> GroupMissionParticipant? {
        if row.participantId == nil && row.participantName == nil { return nil }
        guard let id = row.participantId, let name = row.participantName else {
            throw AppFailure.validation("お題の参加者情報が不正です")
        }
        try validateMissionDate(row.missionDate)
        guard (0...7).contains(row.rotationOrderSnapshot) else {
            throw AppFailure.validation("お題の参加順が不正です")
        }
        return GroupMissionParticipant(missionID: row.missionId, groupID: row.groupId,
            missionDate: row.missionDate,
            missionStatus: try missionStatus(row.missionStatus),
            promptText: row.promptText, setterID: row.setterId,
            participantID: id, participantName: name,
            participantAvatar: try asset(bucket: "avatars", path: row.participantAvatarPath),
            rotationOrderSnapshot: row.rotationOrderSnapshot,
            isActive: row.participantIsActive, answered: row.answered,
            answerID: row.answerId, answerPhotoID: row.answerPhotoId,
            answerCreatedAt: row.answerCreatedAt,
            photoAsset: try asset(bucket: "photos", path: row.photoAssetPath),
            latestApprovedRakugakiAsset: try asset(bucket: "rakugakis",
                path: row.latestApprovedRakugakiAssetPath))
    }

    static func answer(_ row: GroupAnswerRowDTO) -> GroupAnswer {
        GroupAnswer(id: row.id, missionID: row.missionId, userID: row.userId,
            photoID: row.photoId, createdAt: row.createdAt, updatedAt: row.updatedAt)
    }

    static func notification(_ row: NotificationDTO) -> GroupNotification {
        GroupNotification(id: row.id, recipientID: row.recipientId,
            actorID: row.actorId, eventType: row.eventType,
            groupID: row.groupId, missionID: row.missionId, photoID: row.photoId,
            payload: row.payload, readAt: row.readAt, createdAt: row.createdAt)
    }

    private static func missionStatus(_ raw: String) throws -> GroupMissionStatus {
        guard let status = GroupMissionStatus(rawValue: raw) else {
            throw AppFailure.validation("お題状態が不正です")
        }
        return status
    }

    private static func validateMissionDate(_ value: String) throws {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#,
                          options: .regularExpression) != nil else {
            throw AppFailure.validation("お題の日付形式が不正です")
        }
    }

    private static func asset(bucket: String, path: String?) throws -> AssetReference? {
        guard let path else { return nil }
        guard let reference = AssetReference(bucket: bucket, path: path) else {
            throw AppFailure.validation("画像pathが不正です")
        }
        return reference
    }
}
