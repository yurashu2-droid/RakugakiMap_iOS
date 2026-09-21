import CoreData
import Foundation
import MapGrapherCore

enum SubmissionStoreError: Error, Equatable {
    case unreadableStore
    case invalidSubmission
    case duplicateID
    case missingOrExpiredLease
    case immutableFieldsChanged
    case invalidTransition
}

extension SubmissionStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadableStore: return "保存データを開けません"
        case .duplicateID: return "同じ下書きが既にあります"
        case .missingOrExpiredLease: return "投稿の処理権限が失効しました"
        case .invalidSubmission, .immutableFieldsChanged, .invalidTransition:
            return "下書きの状態が不正です"
        }
    }

    var recoverySuggestion: String? {
        if self == .unreadableStore {
            return "データを削除せず、アプリの更新またはサポートを確認してください。"
        }
        return nil
    }
}

final class CoreDataSubmissionStore: SubmissionStoring, @unchecked Sendable {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(storeURL: URL? = nil) async throws {
        let url = try storeURL ?? PersistentContainerFactory.defaultStoreURL()
        let container = try await PersistentContainerFactory.make(storeURL: url)
        self.container = container
        self.context = container.newBackgroundContext()
        self.context.mergePolicy = NSMergePolicy(merge: .errorMergePolicyType)
    }

    func insertDraft(_ submission: PendingSubmission) async throws {
        guard submission.schemaVersion == 1,
              submission.state == .draft ||
                (submission.state == .queued && submission.dependsOn != nil &&
                 submission.kind != .photo && submission.resumeStage == .upload &&
                 submission.attemptCount == 0 && submission.nextAttemptAt == nil &&
                 submission.lastFailure == nil),
              submission.leaseOwner == nil, submission.leaseExpiresAt == nil,
              submission.remoteID == nil else { throw SubmissionStoreError.invalidSubmission }
        let encoded = try SubmissionSnapshot(submission).encoded()
        try await context.perform { [self] in
            let context = self.context
            guard try Self.fetch(id: submission.id, context: context) == nil else {
                throw SubmissionStoreError.duplicateID
            }
            if submission.state == .queued {
                guard let dependencyID = submission.dependsOn,
                      let dependency = try Self.fetch(id: dependencyID, context: context),
                      dependency.value(forKey: "ownerID") as? String == submission.ownerID.uuidString
                else { throw SubmissionStoreError.invalidSubmission }
            }
            let record = NSEntityDescription.insertNewObject(forEntityName: "SubmissionRecord", into: context)
            Self.set(record, submission: submission, snapshot: encoded)
            do {
                try context.save()
            } catch {
                context.rollback()
                throw SubmissionStoreError.unreadableStore
            }
        }
    }

    func listPending(ownerID: UUID) async throws -> [PendingSubmission] {
        try await context.perform { [self] in
            let context = self.context
            let request = NSFetchRequest<NSManagedObject>(entityName: "SubmissionRecord")
            request.predicate = NSPredicate(
                format: "ownerID == %@ AND state != %@ AND state != %@",
                ownerID.uuidString, SubmissionState.completed.rawValue,
                SubmissionState.cancelled.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).map(Self.decode)
        }
    }

    func completedRemoteID(for dependencyID: UUID, ownerID: UUID) async throws -> UUID? {
        try await context.perform { [self] in
            let context = self.context
            guard let record = try Self.fetch(id: dependencyID, context: context),
                  record.value(forKey: "ownerID") as? String == ownerID.uuidString,
                  record.value(forKey: "state") as? String == SubmissionState.completed.rawValue
            else { return nil }
            return try Self.decode(record).remoteID
        }
    }

    func claim(id: UUID, ownerID: UUID, leaseOwner: UUID,
               leaseExpiresAt: Date) async throws -> PendingSubmission? {
        return try await context.perform { [self] in
            let context = self.context
            let now = Date()
            guard leaseExpiresAt > now else { throw SubmissionStoreError.invalidSubmission }
            let request = NSBatchUpdateRequest(entityName: "SubmissionRecord")
            request.predicate = NSPredicate(
                format: "id == %@ AND ownerID == %@ AND (leaseOwner == nil OR leaseExpiresAt <= %@) AND state != %@ AND state != %@",
                id.uuidString, ownerID.uuidString, now as NSDate,
                SubmissionState.completed.rawValue, SubmissionState.cancelled.rawValue
            )
            request.propertiesToUpdate = [
                "leaseOwner": leaseOwner.uuidString,
                "leaseExpiresAt": leaseExpiresAt
            ]
            request.resultType = .updatedObjectsCountResultType
            let result = try context.execute(request) as? NSBatchUpdateResult
            guard (result?.result as? Int) == 1 else { return nil }
            context.reset()
            guard let record = try Self.fetch(id: id, context: context) else {
                throw SubmissionStoreError.unreadableStore
            }
            return try Self.decode(record)
        }
    }

    func save(_ submission: PendingSubmission, leaseOwner: UUID) async throws {
        let encoded = try SubmissionSnapshot(submission).encoded()
        try await context.perform { [self] in
            let context = self.context
            guard let record = try Self.fetch(id: submission.id, context: context) else {
                throw SubmissionStoreError.invalidSubmission
            }
            let previous = try Self.decode(record)
            guard previous.ownerID == submission.ownerID,
                  previous.schemaVersion == submission.schemaVersion,
                  previous.kind == submission.kind,
                  previous.payloadData == submission.payloadData,
                  previous.localFilePaths == submission.localFilePaths,
                  previous.assetPaths == submission.assetPaths,
                  previous.dependsOn == submission.dependsOn,
                  previous.createdAt == submission.createdAt else {
                throw SubmissionStoreError.immutableFieldsChanged
            }
            guard previous.leaseOwner == leaseOwner,
                  previous.leaseExpiresAt.map({ $0 > Date() }) == true,
                  submission.leaseOwner == leaseOwner,
                  submission.leaseExpiresAt == previous.leaseExpiresAt else {
                throw SubmissionStoreError.missingOrExpiredLease
            }
            guard previous.replacingProgress(
                state: submission.state, resumeStage: submission.resumeStage,
                remoteID: submission.remoteID, attemptCount: submission.attemptCount,
                nextAttemptAt: submission.nextAttemptAt, lastFailure: submission.lastFailure,
                leaseOwner: leaseOwner, leaseExpiresAt: submission.leaseExpiresAt,
                updatedAt: submission.updatedAt
            ) == submission else { throw SubmissionStoreError.invalidSubmission }
            if previous.state != submission.state {
                let dependencyID = previous.dependsOn
                let dependencyRemoteID: UUID?
                if let dependencyID,
                   let dependency = try Self.fetch(id: dependencyID, context: context),
                   dependency.value(forKey: "ownerID") as? String == previous.ownerID.uuidString,
                   dependency.value(forKey: "state") as? String == SubmissionState.completed.rawValue {
                    dependencyRemoteID = try Self.decode(dependency).remoteID
                } else {
                    dependencyRemoteID = nil
                }
                guard SubmissionTransition.allows(
                    from: previous.state, to: submission.state,
                    requiresRemoteDependency: dependencyID != nil,
                    dependencyRemoteID: dependencyRemoteID,
                    resumeStage: previous.resumeStage
                ) else { throw SubmissionStoreError.invalidTransition }
            }
            // 同じleaseのまま更新する。異なる処理が取得したleaseを上書きしない。
            let request = NSBatchUpdateRequest(entityName: "SubmissionRecord")
            request.predicate = NSPredicate(
                format: "id == %@ AND ownerID == %@ AND leaseOwner == %@ AND leaseExpiresAt > %@",
                submission.id.uuidString, submission.ownerID.uuidString,
                leaseOwner.uuidString, Date() as NSDate
            )
            let remoteValue: Any = submission.remoteID.map { $0.uuidString as Any } ?? NSNull()
            request.propertiesToUpdate = [
                "state": submission.state.rawValue,
                "remoteID": remoteValue,
                "snapshot": encoded
            ]
            request.resultType = .updatedObjectsCountResultType
            let result = try context.execute(request) as? NSBatchUpdateResult
            guard (result?.result as? Int) == 1 else {
                throw SubmissionStoreError.missingOrExpiredLease
            }
            context.reset()
        }
    }

    func release(id: UUID, ownerID: UUID, leaseOwner: UUID) async throws {
        try await context.perform { [self] in
            let context = self.context
            guard let record = try Self.fetch(id: id, context: context),
                  record.value(forKey: "ownerID") as? String == ownerID.uuidString,
                  record.value(forKey: "leaseOwner") as? String == leaseOwner.uuidString
            else { throw SubmissionStoreError.missingOrExpiredLease }
            let request = NSBatchUpdateRequest(entityName: "SubmissionRecord")
            request.predicate = NSPredicate(format: "id == %@ AND ownerID == %@ AND leaseOwner == %@",
                                            id.uuidString, ownerID.uuidString, leaseOwner.uuidString)
            request.propertiesToUpdate = ["leaseOwner": NSNull(), "leaseExpiresAt": NSNull()]
            request.resultType = .updatedObjectsCountResultType
            let result = try context.execute(request) as? NSBatchUpdateResult
            guard (result?.result as? Int) == 1 else {
                throw SubmissionStoreError.missingOrExpiredLease
            }
            context.reset()
        }
    }

    private static func fetch(id: UUID, context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SubmissionRecord")
        request.predicate = NSPredicate(format: "id == %@", id.uuidString)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func decode(_ record: NSManagedObject) throws -> PendingSubmission {
        guard let data = record.value(forKey: "snapshot") as? Data else {
            throw SubmissionStoreError.unreadableStore
        }
        let submission: PendingSubmission
        do {
            submission = try SubmissionSnapshot.decoded(data).submission()
        } catch {
            throw SubmissionStoreError.unreadableStore
        }
        guard record.value(forKey: "id") as? String == submission.id.uuidString,
              record.value(forKey: "ownerID") as? String == submission.ownerID.uuidString,
              record.value(forKey: "state") as? String == submission.state.rawValue,
              record.value(forKey: "remoteID") as? String == submission.remoteID?.uuidString else {
            throw SubmissionStoreError.unreadableStore
        }
        return try withLease(
            submission,
            owner: (record.value(forKey: "leaseOwner") as? String).flatMap(UUID.init(uuidString:)),
            until: record.value(forKey: "leaseExpiresAt") as? Date
        )
    }

    private static func withLease(_ submission: PendingSubmission, owner: UUID?,
                                  until: Date?) throws -> PendingSubmission {
        guard let result = PendingSubmission(
            id: submission.id, ownerID: submission.ownerID,
            schemaVersion: submission.schemaVersion, kind: submission.kind,
            payloadData: submission.payloadData, localFilePaths: submission.localFilePaths,
            assetPaths: submission.assetPaths, dependsOn: submission.dependsOn,
            remoteID: submission.remoteID, state: submission.state,
            resumeStage: submission.resumeStage, attemptCount: submission.attemptCount,
            nextAttemptAt: submission.nextAttemptAt, lastFailure: submission.lastFailure,
            leaseOwner: owner, leaseExpiresAt: until,
            createdAt: submission.createdAt, updatedAt: submission.updatedAt
        ) else { throw SubmissionStoreError.unreadableStore }
        return result
    }

    private static func set(_ record: NSManagedObject, submission: PendingSubmission,
                            snapshot: Data) {
        record.setValue(submission.id.uuidString, forKey: "id")
        record.setValue(submission.ownerID.uuidString, forKey: "ownerID")
        record.setValue(submission.state.rawValue, forKey: "state")
        record.setValue(submission.remoteID?.uuidString, forKey: "remoteID")
        record.setValue(submission.leaseOwner?.uuidString, forKey: "leaseOwner")
        record.setValue(submission.leaseExpiresAt, forKey: "leaseExpiresAt")
        record.setValue(submission.createdAt, forKey: "createdAt")
        record.setValue(snapshot, forKey: "snapshot")
    }
}

private struct SubmissionSnapshot: Codable {
    let id: UUID
    let ownerID: UUID
    let schemaVersion: Int
    let kind: SubmissionKind
    let payloadData: Data
    let localFilePaths: [String]
    let assetPaths: [AssetReference]
    let dependsOn: UUID?
    let createdAt: Date
    let remoteID: UUID?
    let state: SubmissionState
    let resumeStage: SubmissionResumeStage
    let attemptCount: Int
    let nextAttemptAt: Date?
    let lastFailureCode: String?
    let lastFailureDetail: String?
    let updatedAt: Date

    init(_ value: PendingSubmission) {
        id = value.id
        ownerID = value.ownerID
        schemaVersion = value.schemaVersion
        kind = value.kind
        payloadData = value.payloadData
        localFilePaths = value.localFilePaths
        assetPaths = value.assetPaths
        dependsOn = value.dependsOn
        createdAt = value.createdAt
        remoteID = value.remoteID
        state = value.state
        resumeStage = value.resumeStage
        attemptCount = value.attemptCount
        nextAttemptAt = value.nextAttemptAt
        let failure = Self.encode(value.lastFailure)
        lastFailureCode = failure.0
        lastFailureDetail = failure.1
        updatedAt = value.updatedAt
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }
    static func decoded(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }

    func submission() throws -> PendingSubmission {
        let failure = try Self.decodeFailure(lastFailureCode, lastFailureDetail)
        guard schemaVersion == 1,
              let result = PendingSubmission(
                id: id, ownerID: ownerID, schemaVersion: schemaVersion,
                kind: kind, payloadData: payloadData,
                localFilePaths: localFilePaths, assetPaths: assetPaths,
                dependsOn: dependsOn, remoteID: remoteID, state: state,
                resumeStage: resumeStage, attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastFailure: failure,
                leaseOwner: nil, leaseExpiresAt: nil,
                createdAt: createdAt, updatedAt: updatedAt
              ) else { throw SubmissionStoreError.unreadableStore }
        return result
    }

    private static func encode(_ failure: AppFailure?) -> (String?, String?) {
        switch failure {
        case .none: return (nil, nil)
        case .offline: return ("offline", nil)
        case .needsLogin: return ("needsLogin", nil)
        case .forbidden: return ("forbidden", nil)
        case .notFound: return ("notFound", nil)
        case .cancelled: return ("cancelled", nil)
        case .validation(let detail): return ("validation", detail)
        case .rateLimited: return ("rateLimited", nil)
        case .outcomeUnknown: return ("outcomeUnknown", nil)
        case .serviceUnavailable: return ("serviceUnavailable", nil)
        }
    }

    private static func decodeFailure(_ code: String?, _ detail: String?) throws -> AppFailure? {
        switch code {
        case nil: return nil
        case "offline": return .offline
        case "needsLogin": return .needsLogin
        case "forbidden": return .forbidden
        case "notFound": return .notFound
        case "cancelled": return .cancelled
        case "validation": return .validation(detail ?? "")
        case "rateLimited": return .rateLimited
        case "outcomeUnknown": return .outcomeUnknown
        case "serviceUnavailable": return .serviceUnavailable
        default: throw SubmissionStoreError.unreadableStore
        }
    }
}
