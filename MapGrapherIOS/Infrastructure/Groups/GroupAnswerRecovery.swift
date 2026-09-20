import Foundation
import MapGrapherCore

struct GroupMissionSnapshot: Sendable {
    let groupID: UUID
    let missionID: UUID
    let missionDate: String
}

@MainActor
protocol GroupMissionSnapshotLookingUp {
    func current(missionID: UUID, context: SessionContext) async throws -> GroupMissionSnapshot?
}

@MainActor
struct GroupsMissionSnapshotLookup: GroupMissionSnapshotLookingUp {
    let groups: any GroupsServing
    func current(missionID: UUID, context: SessionContext) async throws -> GroupMissionSnapshot? {
        let rows = try await groups.summaries(context: context)
        guard let row = rows.first(where: { $0.missionID == missionID }),
              let date = row.missionDate else { return nil }
        return GroupMissionSnapshot(groupID: row.id, missionID: missionID, missionDate: date)
    }
}

@MainActor
protocol MissionAnswerRemote {
    func missionStatus(groupID: UUID, context: SessionContext) async throws -> [GroupMissionParticipant]
    func submitAnswer(missionID: UUID, photoID: UUID,
                      context: SessionContext) async throws -> GroupAnswer
}

@MainActor
struct GroupsMissionAnswerRemote: MissionAnswerRemote {
    let groups: any GroupsServing
    func missionStatus(groupID: UUID, context: SessionContext) async throws -> [GroupMissionParticipant] {
        try await groups.missionStatus(groupID: groupID, context: context)
    }
    func submitAnswer(missionID: UUID, photoID: UUID,
                      context: SessionContext) async throws -> GroupAnswer {
        try await groups.submitAnswer(missionID: missionID, photoID: photoID, context: context)
    }
}

protocol CompletedPhotoLookingUp: Sendable {
    func remoteID(for operationID: UUID, ownerID: UUID) async throws -> UUID?
}

struct SubmissionPhotoLookup: CompletedPhotoLookingUp {
    let submissions: any SubmissionStoring
    func remoteID(for operationID: UUID, ownerID: UUID) async throws -> UUID? {
        try await submissions.completedRemoteID(for: operationID, ownerID: ownerID)
    }
}

/// 回答RPCにrequest IDがないため、応答不明後は照会のみ行い自動再送しない。
@MainActor
final class GroupAnswerRecovery {
    private let journal: GroupAnswerRecoveryStore
    private let photos: any CompletedPhotoLookingUp
    private let remote: any MissionAnswerRemote
    private let session: any SessionProviding
    private var active: Set<UUID> = []

    init(journal: GroupAnswerRecoveryStore, photos: any CompletedPhotoLookingUp,
         remote: any MissionAnswerRemote, session: any SessionProviding) {
        self.journal = journal; self.photos = photos
        self.remote = remote; self.session = session
    }

    func load(operationID: UUID, context: SessionContext) async throws -> GroupAnswerOperation? {
        try await check(context)
        let operation = try await journal.load(id: operationID, ownerID: context.userID)
        try await check(context)
        return operation
    }

    func create(operationID: UUID, groupID: UUID, missionID: UUID,
                missionDate: String, photoOperationID: UUID,
                context: SessionContext) async throws -> GroupAnswerOperation {
        try await check(context)
        guard missionDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#,
                                options: .regularExpression) != nil else {
            throw AppFailure.validation("お題の日付形式が不正です")
        }
        if let existing = try await journal.load(id: operationID, ownerID: context.userID) {
            try await check(context)
            guard existing.groupID == groupID, existing.missionID == missionID,
                  existing.missionDate == missionDate,
                  existing.photoOperationID == photoOperationID else {
                throw AppFailure.validation("同じ回答IDの入力が一致しません")
            }
            return existing
        }
        let status = try await remote.missionStatus(groupID: groupID, context: context)
        try await check(context)
        guard let mine = ownParticipant(status, missionID: missionID,
                missionDate: missionDate, ownerID: context.userID),
              mine.isActive, mine.missionStatus == .open else {
            throw AppFailure.validation("この日の回答には参加できません")
        }
        let now = Date()
        let operation = GroupAnswerOperation(id: operationID, ownerID: context.userID,
            groupID: groupID, missionID: missionID, missionDate: missionDate,
            photoOperationID: photoOperationID, createdAt: now,
            remotePhotoID: nil, remoteAnswerID: nil, phase: .awaitingPhoto, updatedAt: now)
        try await journal.save(operation)
        try await check(context)
        return operation
    }

    func submit(operationID: UUID, context: SessionContext) async throws -> GroupAnswerOperation {
        try await check(context)
        guard active.insert(operationID).inserted else { throw AppFailure.serviceUnavailable }
        defer { active.remove(operationID) }
        guard var operation = try await journal.load(id: operationID, ownerID: context.userID) else {
            throw AppFailure.notFound
        }
        try await check(context)
        if operation.phase == .completed || operation.phase == .needsCorrection { return operation }
        if operation.phase == .submitting || operation.phase == .outcomeUnknown {
            return try await reconcile(operationID: operationID, context: context)
        }
        if operation.remotePhotoID == nil {
            operation.remotePhotoID = try await photos.remoteID(for: operation.photoOperationID,
                                                                ownerID: context.userID)
            try await check(context)
            guard operation.remotePhotoID != nil else { return operation }
            operation.phase = .ready
            operation.updatedAt = Date()
            try await journal.save(operation)
            try await check(context)
        }
        guard let photoID = operation.remotePhotoID else { return operation }
        let rows = try await remote.missionStatus(groupID: operation.groupID, context: context)
        try await check(context)
        guard let mine = ownParticipant(rows, missionID: operation.missionID,
                missionDate: operation.missionDate, ownerID: context.userID),
              mine.isActive, mine.missionStatus == .open else {
            return try await markCorrection(operation, context: context)
        }
        if mine.answered || mine.answerID != nil || mine.answerPhotoID != nil {
            if mine.answerPhotoID == photoID, let answerID = mine.answerID {
                return try await markCompleted(operation, answerID: answerID, context: context)
            }
            return try await markCorrection(operation, context: context)
        }
        operation.phase = .submitting
        operation.updatedAt = Date()
        // 保存が成功して初めて非冪等RPCを1回だけ送る。crash後は照会専用。
        try await journal.save(operation)
        try await check(context)
        let answer: GroupAnswer
        do {
            answer = try await remote.submitAnswer(missionID: operation.missionID,
                                                   photoID: photoID, context: context)
        } catch {
            operation.phase = .outcomeUnknown
            operation.updatedAt = Date()
            try await journal.save(operation)
            guard await session.isCurrent(context) else { throw AppFailure.cancelled }
            return (try? await reconcile(operationID: operationID, context: context)) ?? operation
        }
        try await check(context)
        guard answer.missionID == operation.missionID,
              answer.photoID == photoID, answer.userID == context.userID else {
            return try await markCorrection(operation, context: context)
        }
        return try await markCompleted(operation, answerID: answer.id, context: context)
    }

    /// 再起動後・応答消失後に使う。ここからsubmit_group_answerは呼ばない。
    func reconcile(operationID: UUID, context: SessionContext) async throws -> GroupAnswerOperation {
        try await check(context)
        guard let operation = try await journal.load(id: operationID, ownerID: context.userID) else {
            throw AppFailure.notFound
        }
        try await check(context)
        guard operation.phase == .submitting || operation.phase == .outcomeUnknown else {
            return operation
        }
        guard let photoID = operation.remotePhotoID else { return operation }
        let rows = try await remote.missionStatus(groupID: operation.groupID, context: context)
        try await check(context)
        guard let mine = ownParticipant(rows, missionID: operation.missionID,
                missionDate: operation.missionDate, ownerID: context.userID),
              mine.answerPhotoID == photoID, let answerID = mine.answerID else {
            return try await markCorrection(operation, context: context)
        }
        return try await markCompleted(operation, answerID: answerID, context: context)
    }

    func list(context: SessionContext) async throws -> [GroupAnswerOperation] {
        try await check(context)
        let rows = try await journal.list(ownerID: context.userID)
        try await check(context)
        return rows
    }

    private func ownParticipant(_ rows: [GroupMissionParticipant], missionID: UUID,
                                missionDate: String, ownerID: UUID) -> GroupMissionParticipant? {
        rows.first { $0.missionID == missionID && $0.missionDate == missionDate &&
            $0.participantID == ownerID }
    }

    private func markCorrection(_ old: GroupAnswerOperation,
                                context: SessionContext) async throws -> GroupAnswerOperation {
        var operation = old
        operation.phase = .needsCorrection
        operation.updatedAt = Date()
        try await journal.save(operation)
        try await check(context)
        return operation
    }

    private func markCompleted(_ old: GroupAnswerOperation,
                               answerID: UUID,
                               context: SessionContext) async throws -> GroupAnswerOperation {
        var operation = old
        operation.phase = .completed
        operation.remoteAnswerID = answerID
        operation.updatedAt = Date()
        try await journal.save(operation)
        try await check(context)
        return operation
    }

    private func check(_ context: SessionContext) async throws {
        try Task.checkCancellation()
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
    }
}
