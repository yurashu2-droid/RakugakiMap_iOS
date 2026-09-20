import Foundation
import MapGrapherCore
import SwiftUI

/// グループ画面が実データか画面試作かを表示するためのモード。
enum GroupUIDataMode: Sendable, Equatable {
    case fake
    case live
}

enum GroupUIError: Error, Equatable, Sendable {
    case missingSession
    case invalidInput
    case permissionDenied
    case notFound
    case offline
    case serviceUnavailable
    case cancelled
    case operationFailed
}

@MainActor
enum GroupUIContext {
    static let fakeUserID = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!

    static func resolve(_ context: SessionContext?, dataMode: GroupUIDataMode) throws -> SessionContext {
        if let context { return context }
        guard dataMode == .fake else { throw GroupUIError.missingSession }
        return SessionContext(userID: fakeUserID,
                              epoch: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!)
    }
}

/// GroupsServingを使う画面用の合成エラーと表示文言の境界。
enum GroupUIMessage {
    static func errorKey(for error: Error?) -> LocalizedStringKey {
        if let error = error as? GroupUIError {
            switch error {
            case .missingSession:
                return "groups.error.session"
            case .invalidInput:
                return "groups.error.invalid"
            case .permissionDenied:
                return "groups.error.permission"
            case .notFound:
                return "groups.error.not-found"
            case .offline:
                return "groups.error.offline"
            case .serviceUnavailable, .operationFailed:
                return "groups.error"
            case .cancelled:
                return "groups.error.cancelled"
            }
        }
        if let error = error as? AppFailure {
            switch error {
            case .offline:
                return "groups.error.offline"
            case .needsLogin:
                return "groups.error.session"
            case .forbidden:
                return "groups.error.permission"
            case .notFound:
                return "groups.error.not-found"
            case .cancelled:
                return "groups.error.cancelled"
            case .validation:
                return "groups.error.invalid"
            case .rateLimited:
                return "groups.error.rate-limited"
            case .outcomeUnknown, .serviceUnavailable:
                return "groups.error"
            }
        }
        return "groups.error"
    }
}

@MainActor
struct GroupActionNotice: View {
    let dataMode: GroupUIDataMode

    var body: some View {
        Group {
            if dataMode == .fake {
                Text("groups.notice.fake")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("groups.notice.fake")
            } else {
                Text("groups.operation.success")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("groups.operation.success")
            }
        }
    }
}

/// UIテストと未接続環境で使う合成サービス。実通信を成功扱いにしないため、画面は常にfakeモードを表示する。
@MainActor
final class FakeGroupsServing: GroupsServing {
    let dataMode: GroupUIDataMode = .fake

    private var records: [UUID: GroupRecord]
    private var summariesValue: [UUID: GroupSummary]
    private var membersValue: [UUID: [GroupMember]]
    private var participantsValue: [UUID: [GroupMissionParticipant]]
    private var invitationRows: [UUID: GroupInvitation]
    private var invitationSummaries: [GroupInvitationSummary]
    private var notificationRows: [GroupNotification]

    init() {
        let now = Date()
        let groupID = UUID(uuidString: "00000000-0000-4000-8000-000000000211")!
        let missionID = UUID(uuidString: "00000000-0000-4000-8000-000000000212")!
        let memberID = UUID(uuidString: "00000000-0000-4000-8000-000000000213")!
        let invitationID = UUID(uuidString: "00000000-0000-4000-8000-000000000214")!
        let invitedGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000215")!
        let notificationID = UUID(uuidString: "00000000-0000-4000-8000-000000000216")!
        let context = SessionContext(userID: GroupUIContext.fakeUserID,
                                     epoch: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!)
        let date = GroupMissionDate.todayString(now: now)
        let record = GroupRecord(
            id: groupID,
            ownerID: context.userID,
            clientRequestID: UUID(uuidString: "00000000-0000-4000-8000-000000000217")!,
            name: "週末の発見隊",
            description: "近所で見つけたものを共有するグループです。",
            archivedAt: nil,
            createdAt: now.addingTimeInterval(-86_400 * 4),
            updatedAt: now.addingTimeInterval(-3_600)
        )
        let summary = GroupSummary(
            id: groupID,
            name: record.name,
            description: record.description,
            ownerID: record.ownerID,
            isOwner: true,
            memberCount: 2,
            missionID: missionID,
            missionDate: date,
            missionStatus: .open,
            promptText: "今日見つけた丸いもの",
            setterID: context.userID,
            setterName: "あなた",
            answeredCount: 1,
            participantCount: 2,
            hasAnswered: false
        )
        let owner = GroupMember(
            id: context.userID,
            displayName: "あなた",
            userUniqueID: "demo-owner",
            avatar: nil,
            role: .owner,
            status: .active,
            rotationOrder: 0,
            joinedAt: record.createdAt,
            answeredToday: false,
            isTodaySetter: true
        )
        let member = GroupMember(
            id: memberID,
            displayName: "あおい",
            userUniqueID: "aoi-map",
            avatar: nil,
            role: .member,
            status: .active,
            rotationOrder: 1,
            joinedAt: record.createdAt.addingTimeInterval(300),
            answeredToday: true,
            isTodaySetter: false
        )
        let participantOwner = GroupMissionParticipant(
            missionID: missionID,
            groupID: groupID,
            missionDate: date,
            missionStatus: .open,
            promptText: summary.promptText,
            setterID: context.userID,
            participantID: context.userID,
            participantName: "あなた",
            participantAvatar: nil,
            rotationOrderSnapshot: 0,
            isActive: true,
            answered: false,
            answerID: nil,
            answerPhotoID: nil,
            answerCreatedAt: nil,
            photoAsset: nil,
            latestApprovedRakugakiAsset: nil
        )
        let participantMember = GroupMissionParticipant(
            missionID: missionID,
            groupID: groupID,
            missionDate: date,
            missionStatus: .open,
            promptText: summary.promptText,
            setterID: context.userID,
            participantID: memberID,
            participantName: member.displayName,
            participantAvatar: nil,
            rotationOrderSnapshot: 1,
            isActive: true,
            answered: true,
            answerID: UUID(uuidString: "00000000-0000-4000-8000-000000000218"),
            answerPhotoID: UUID(uuidString: "00000000-0000-4000-8000-000000000219"),
            answerCreatedAt: now.addingTimeInterval(-1_800),
            photoAsset: nil,
            latestApprovedRakugakiAsset: nil
        )
        let invitation = GroupInvitationSummary(
            id: invitationID,
            groupID: invitedGroupID,
            groupName: "街角スケッチ部",
            inviterID: memberID,
            inviterName: "あおい",
            memberCount: 3,
            expiresAt: now.addingTimeInterval(86_400),
            createdAt: now.addingTimeInterval(-1_200)
        )
        let notification = GroupNotification(
            id: notificationID,
            recipientID: context.userID,
            actorID: memberID,
            eventType: "GROUP_INVITED",
            groupID: invitedGroupID,
            missionID: nil,
            photoID: nil,
            payload: [:],
            readAt: nil,
            createdAt: now.addingTimeInterval(-600)
        )
        records = [groupID: record]
        summariesValue = [groupID: summary]
        membersValue = [groupID: [owner, member]]
        participantsValue = [groupID: [participantOwner, participantMember]]
        invitationRows = [:]
        invitationSummaries = [invitation]
        notificationRows = [notification]
    }

    func createGroup(requestID: UUID, name: String, description: String,
                     context: SessionContext) async throws -> GroupRecord {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= 80,
              description.count <= 500 else { throw AppFailure.validation("グループ名を確認してください") }
        let now = Date()
        let groupID = UUID()
        let missionID = UUID()
        let record = GroupRecord(id: groupID, ownerID: context.userID,
                                 clientRequestID: requestID, name: normalizedName,
                                 description: description, archivedAt: nil,
                                 createdAt: now, updatedAt: now)
        records[groupID] = record
        summariesValue[groupID] = GroupSummary(
            id: groupID, name: normalizedName, description: description,
            ownerID: context.userID, isOwner: true, memberCount: 1,
            missionID: missionID, missionDate: GroupMissionDate.todayString(now: now),
            missionStatus: .awaitingPrompt, promptText: nil,
            setterID: context.userID, setterName: "あなた", answeredCount: 0,
            participantCount: 1, hasAnswered: false
        )
        membersValue[groupID] = [GroupMember(
            id: context.userID, displayName: "あなた", userUniqueID: "demo-owner",
            avatar: nil, role: .owner, status: .active, rotationOrder: 0,
            joinedAt: now, answeredToday: false, isTodaySetter: true
        )]
        participantsValue[groupID] = [GroupMissionParticipant(
            missionID: missionID, groupID: groupID,
            missionDate: GroupMissionDate.todayString(now: now),
            missionStatus: .awaitingPrompt, promptText: nil, setterID: context.userID,
            participantID: context.userID, participantName: "あなた", participantAvatar: nil,
            rotationOrderSnapshot: 0, isActive: true, answered: false, answerID: nil,
            answerPhotoID: nil, answerCreatedAt: nil, photoAsset: nil,
            latestApprovedRakugakiAsset: nil
        )]
        return record
    }

    func updateGroup(id: UUID, name: String, description: String,
                     context: SessionContext) async throws -> GroupRecord {
        guard let old = records[id], old.ownerID == context.userID,
              let summary = summariesValue[id] else { throw AppFailure.forbidden }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= 80,
              description.count <= 500 else { throw AppFailure.validation("グループ名を確認してください") }
        let now = Date()
        let updated = GroupRecord(id: old.id, ownerID: old.ownerID,
                                  clientRequestID: old.clientRequestID,
                                  name: normalizedName, description: description,
                                  archivedAt: old.archivedAt, createdAt: old.createdAt,
                                  updatedAt: now)
        records[id] = updated
        summariesValue[id] = replacing(summary, name: normalizedName, description: description)
        return updated
    }

    func summaries(context: SessionContext) async throws -> [GroupSummary] {
        summariesValue.values.filter { records[$0.id]?.archivedAt == nil }
            .sorted { $0.name < $1.name }
    }

    func members(groupID: UUID, context: SessionContext) async throws -> [GroupMember] {
        guard summariesValue[groupID] != nil else { throw AppFailure.notFound }
        return membersValue[groupID] ?? []
    }

    func invite(groupID: UUID, userUniqueID: String,
                context: SessionContext) async throws -> GroupInvitation {
        guard let summary = summariesValue[groupID], summary.isOwner,
              !userUniqueID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure.forbidden
        }
        let now = Date()
        let invitation = GroupInvitation(id: UUID(), groupID: groupID,
                                         inviterID: context.userID,
                                         inviteeID: UUID(), status: .pending,
                                         expiresAt: now.addingTimeInterval(86_400),
                                         respondedAt: nil, createdAt: now, updatedAt: now)
        invitationRows[invitation.id] = invitation
        return invitation
    }

    func cancelInvitation(id: UUID, context: SessionContext) async throws -> GroupInvitation {
        guard let old = invitationRows[id], old.inviterID == context.userID else {
            throw AppFailure.notFound
        }
        let updated = GroupInvitation(id: old.id, groupID: old.groupID,
                                      inviterID: old.inviterID, inviteeID: old.inviteeID,
                                      status: .canceled, expiresAt: old.expiresAt,
                                      respondedAt: old.respondedAt, createdAt: old.createdAt,
                                      updatedAt: Date())
        invitationRows[id] = updated
        return updated
    }

    func invitations(context: SessionContext) async throws -> [GroupInvitationSummary] {
        invitationSummaries
    }

    func respondInvitation(id: UUID, accepted: Bool,
                           context: SessionContext) async throws -> GroupInvitation {
        guard let incoming = invitationSummaries.first(where: { $0.id == id }) else {
            throw AppFailure.notFound
        }
        let now = Date()
        let result = GroupInvitation(id: incoming.id, groupID: incoming.groupID,
                                     inviterID: incoming.inviterID, inviteeID: context.userID,
                                     status: accepted ? .accepted : .declined,
                                     expiresAt: incoming.expiresAt, respondedAt: now,
                                     createdAt: incoming.createdAt, updatedAt: now)
        invitationSummaries.removeAll { $0.id == id }
        if accepted {
            let groupID = incoming.groupID
            let missionID = UUID()
            let record = GroupRecord(id: groupID, ownerID: incoming.inviterID,
                                     clientRequestID: UUID(), name: incoming.groupName,
                                     description: "招待されたグループです。", archivedAt: nil,
                                     createdAt: incoming.createdAt, updatedAt: now)
            records[groupID] = record
            summariesValue[groupID] = GroupSummary(
                id: groupID, name: incoming.groupName, description: record.description,
                ownerID: incoming.inviterID, isOwner: false, memberCount: incoming.memberCount + 1,
                missionID: missionID, missionDate: GroupMissionDate.todayString(now: now),
                missionStatus: .awaitingPrompt, promptText: nil, setterID: incoming.inviterID,
                setterName: incoming.inviterName, answeredCount: 0,
                participantCount: incoming.memberCount + 1, hasAnswered: false
            )
            membersValue[groupID] = [GroupMember(
                id: context.userID, displayName: "あなた", userUniqueID: "demo-owner",
                avatar: nil, role: .member, status: .active, rotationOrder: 0,
                joinedAt: now, answeredToday: false, isTodaySetter: false
            )]
            participantsValue[groupID] = [GroupMissionParticipant(
                missionID: missionID, groupID: groupID,
                missionDate: GroupMissionDate.todayString(now: now),
                missionStatus: .awaitingPrompt, promptText: nil,
                setterID: incoming.inviterID, participantID: context.userID,
                participantName: "あなた", participantAvatar: nil, rotationOrderSnapshot: 0,
                isActive: true, answered: false, answerID: nil, answerPhotoID: nil,
                answerCreatedAt: nil, photoAsset: nil, latestApprovedRakugakiAsset: nil
            )]
        }
        return result
    }

    func leave(groupID: UUID, context: SessionContext) async throws {
        guard let summary = summariesValue[groupID] else { throw AppFailure.notFound }
        guard !summary.isOwner else { throw AppFailure.forbidden }
        membersValue[groupID]?.removeAll { $0.id == context.userID }
        summariesValue[groupID] = replacing(summary, memberCount: max(0, summary.memberCount - 1))
    }

    func removeMember(groupID: UUID, memberID: UUID, context: SessionContext) async throws {
        guard let summary = summariesValue[groupID], summary.isOwner,
              memberID != summary.ownerID else { throw AppFailure.forbidden }
        membersValue[groupID]?.removeAll { $0.id == memberID }
        summariesValue[groupID] = replacing(summary, memberCount: Int64(membersValue[groupID]?.count ?? 0))
    }

    func transferOwnership(groupID: UUID, newOwnerID: UUID,
                           context: SessionContext) async throws -> GroupRecord {
        guard let old = records[groupID], old.ownerID == context.userID,
              let summary = summariesValue[groupID],
              membersValue[groupID]?.contains(where: { $0.id == newOwnerID && $0.status == .active }) == true else {
            throw AppFailure.forbidden
        }
        let now = Date()
        let updated = GroupRecord(id: old.id, ownerID: newOwnerID,
                                  clientRequestID: old.clientRequestID, name: old.name,
                                  description: old.description, archivedAt: old.archivedAt,
                                  createdAt: old.createdAt, updatedAt: now)
        records[groupID] = updated
        summariesValue[groupID] = replacing(summary, ownerID: newOwnerID, isOwner: false)
        membersValue[groupID] = membersValue[groupID]?.map { member in
            GroupMember(id: member.id, displayName: member.displayName,
                        userUniqueID: member.userUniqueID, avatar: member.avatar,
                        role: member.id == newOwnerID ? .owner : .member,
                        status: member.status, rotationOrder: member.rotationOrder,
                        joinedAt: member.joinedAt, answeredToday: member.answeredToday,
                        isTodaySetter: member.isTodaySetter)
        } ?? []
        return updated
    }

    func archive(groupID: UUID, context: SessionContext) async throws -> GroupRecord {
        guard let old = records[groupID], old.ownerID == context.userID else { throw AppFailure.forbidden }
        let updated = GroupRecord(id: old.id, ownerID: old.ownerID,
                                 clientRequestID: old.clientRequestID, name: old.name,
                                 description: old.description, archivedAt: Date(),
                                 createdAt: old.createdAt, updatedAt: Date())
        records[groupID] = updated
        return updated
    }

    func reassignSetter(missionID: UUID, context: SessionContext) async throws -> GroupMission {
        guard let entry = missionEntry(missionID), let summary = summariesValue[entry.groupID],
              summary.isOwner else { throw AppFailure.forbidden }
        let nextSetter = membersValue[entry.groupID]?.first(where: { $0.status == .active && $0.id != summary.setterID })
        let updatedSummary = replacing(summary, setterID: nextSetter?.id ?? context.userID,
                                       setterName: nextSetter?.displayName ?? "あなた")
        summariesValue[entry.groupID] = updatedSummary
        return makeMission(from: updatedSummary, missionID: missionID)
    }

    func setPrompt(missionID: UUID, text: String,
                   context: SessionContext) async throws -> GroupMission {
        guard let entry = missionEntry(missionID), let summary = summariesValue[entry.groupID],
              summary.setterID == context.userID,
              summary.missionStatus == .awaitingPrompt else { throw AppFailure.forbidden }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 160 else {
            throw AppFailure.validation("お題を入力してください")
        }
        let updatedSummary = replacing(summary, missionStatus: .open, promptText: normalized)
        summariesValue[entry.groupID] = updatedSummary
        participantsValue[entry.groupID] = participantsValue[entry.groupID]?.map { participant in
            participant.missionID == missionID
                ? GroupMissionParticipant(
                    missionID: participant.missionID, groupID: participant.groupID,
                    missionDate: participant.missionDate, missionStatus: .open,
                    promptText: normalized, setterID: context.userID,
                    participantID: participant.participantID, participantName: participant.participantName,
                    participantAvatar: participant.participantAvatar,
                    rotationOrderSnapshot: participant.rotationOrderSnapshot,
                    isActive: participant.isActive, answered: participant.answered,
                    answerID: participant.answerID, answerPhotoID: participant.answerPhotoID,
                    answerCreatedAt: participant.answerCreatedAt, photoAsset: participant.photoAsset,
                    latestApprovedRakugakiAsset: participant.latestApprovedRakugakiAsset
                )
                : participant
        }
        return makeMission(from: updatedSummary, missionID: missionID)
    }

    func missionStatus(groupID: UUID, context: SessionContext) async throws -> [GroupMissionParticipant] {
        guard summariesValue[groupID] != nil else { throw AppFailure.notFound }
        return participantsValue[groupID] ?? []
    }

    func submitAnswer(missionID: UUID, photoID: UUID,
                      context: SessionContext) async throws -> GroupAnswer {
        guard let entry = missionEntry(missionID), let index = participantsValue[entry.groupID]?.firstIndex(where: {
            $0.missionID == missionID && $0.participantID == context.userID
        }), let participant = participantsValue[entry.groupID]?[index],
              participant.isActive, participant.missionStatus == .open,
              GroupMissionDate.state(for: participant.missionDate) == .today,
              !participant.answered else { throw AppFailure.validation("このお題には回答できません") }
        let answer = GroupAnswer(id: UUID(), missionID: missionID, userID: context.userID,
                                 photoID: photoID, createdAt: Date(), updatedAt: Date())
        participantsValue[entry.groupID]?[index] = GroupMissionParticipant(
            missionID: participant.missionID, groupID: participant.groupID,
            missionDate: participant.missionDate, missionStatus: participant.missionStatus,
            promptText: participant.promptText, setterID: participant.setterID,
            participantID: participant.participantID, participantName: participant.participantName,
            participantAvatar: participant.participantAvatar,
            rotationOrderSnapshot: participant.rotationOrderSnapshot,
            isActive: participant.isActive, answered: true, answerID: answer.id,
            answerPhotoID: photoID, answerCreatedAt: answer.createdAt,
            photoAsset: participant.photoAsset,
            latestApprovedRakugakiAsset: participant.latestApprovedRakugakiAsset
        )
        return answer
    }

    func withdrawAnswer(missionID: UUID, context: SessionContext) async throws {
        guard let entry = missionEntry(missionID), let index = participantsValue[entry.groupID]?.firstIndex(where: {
            $0.missionID == missionID && $0.participantID == context.userID
        }), let participant = participantsValue[entry.groupID]?[index] else { throw AppFailure.notFound }
        participantsValue[entry.groupID]?[index] = GroupMissionParticipant(
            missionID: participant.missionID, groupID: participant.groupID,
            missionDate: participant.missionDate, missionStatus: participant.missionStatus,
            promptText: participant.promptText, setterID: participant.setterID,
            participantID: participant.participantID, participantName: participant.participantName,
            participantAvatar: participant.participantAvatar,
            rotationOrderSnapshot: participant.rotationOrderSnapshot,
            isActive: participant.isActive, answered: false, answerID: nil,
            answerPhotoID: nil, answerCreatedAt: nil, photoAsset: participant.photoAsset,
            latestApprovedRakugakiAsset: participant.latestApprovedRakugakiAsset
        )
    }

    func notifications(limit: Int, before: String?,
                       context: SessionContext) async throws -> [GroupNotification] {
        guard (1...50).contains(limit) else { throw AppFailure.validation("通知件数が不正です") }
        return Array(notificationRows.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    func markNotificationRead(id: UUID, context: SessionContext) async throws -> GroupNotification {
        guard let index = notificationRows.firstIndex(where: { $0.id == id }),
              notificationRows[index].recipientID == context.userID else { throw AppFailure.notFound }
        let old = notificationRows[index]
        let updated = GroupNotification(id: old.id, recipientID: old.recipientID,
                                        actorID: old.actorID, eventType: old.eventType,
                                        groupID: old.groupID, missionID: old.missionID,
                                        photoID: old.photoID, payload: old.payload,
                                        readAt: old.readAt ?? Date(), createdAt: old.createdAt)
        notificationRows[index] = updated
        return updated
    }

    private func missionEntry(_ missionID: UUID) -> GroupMissionParticipant? {
        participantsValue.values.flatMap { $0 }.first { $0.missionID == missionID }
    }

    private func makeMission(from summary: GroupSummary, missionID: UUID) -> GroupMission {
        let date = summary.missionDate ?? GroupMissionDate.todayString()
        return GroupMission(id: missionID, groupID: summary.id, missionDate: date,
                            setterID: summary.setterID, promptText: summary.promptText,
                            status: summary.missionStatus ?? .awaitingPrompt,
                            promptSetAt: summary.promptText == nil ? nil : Date(),
                            closesAt: Date().addingTimeInterval(86_400),
                            createdAt: Date().addingTimeInterval(-86_400), updatedAt: Date())
    }

    private func replacing(_ summary: GroupSummary,
                           name: String? = nil,
                           description: String? = nil,
                           ownerID: UUID? = nil,
                           isOwner: Bool? = nil,
                           memberCount: Int64? = nil,
                           missionStatus: GroupMissionStatus? = nil,
                           promptText: String?? = nil,
                           setterID: UUID?? = nil,
                           setterName: String?? = nil) -> GroupSummary {
        GroupSummary(id: summary.id, name: name ?? summary.name,
                     description: description ?? summary.description,
                     ownerID: ownerID ?? summary.ownerID,
                     isOwner: isOwner ?? summary.isOwner,
                     memberCount: memberCount ?? summary.memberCount,
                     missionID: summary.missionID, missionDate: summary.missionDate,
                     missionStatus: missionStatus ?? summary.missionStatus,
                     promptText: promptText ?? summary.promptText,
                     setterID: setterID ?? summary.setterID,
                     setterName: setterName ?? summary.setterName,
                     answeredCount: summary.answeredCount,
                     participantCount: summary.participantCount,
                     hasAnswered: summary.hasAnswered)
    }
}
