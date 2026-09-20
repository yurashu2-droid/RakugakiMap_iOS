import Foundation

public actor SubmissionCoordinator {
    private let store: any SubmissionStoring
    private let session: any SessionProviding
    private let transport: any SubmissionTransport
    private let clock: @Sendable () -> Date
    private var active: Set<UUID> = []

    public init(store: any SubmissionStoring, session: any SessionProviding,
                transport: any SubmissionTransport, clock: @escaping @Sendable () -> Date = Date.init) {
        self.store = store; self.session = session; self.transport = transport; self.clock = clock
    }

    @discardableResult
    public func enqueue(draftID: UUID, context: SessionContext) async throws -> UUID {
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        let rows = try await store.listPending(ownerID: context.userID)
        guard let row = rows.first(where: { $0.id == draftID }) else { throw AppFailure.notFound }
        guard row.state == .draft || row.state == .retryWaiting ||
              row.state == .needsLogin || row.state == .outcomeUnknown else {
            throw AppFailure.validation("この投稿は開始できません")
        }
        guard let lease = try await store.claim(id: draftID, ownerID: context.userID,
                                                leaseOwner: UUID(), leaseExpiresAt: clock().addingTimeInterval(300)) else {
            throw AppFailure.serviceUnavailable
        }
        do {
            let queued = try changed(lease,
                                     state: lease.state == .outcomeUnknown ? .outcomeUnknown : .queued,
                                     stage: lease.resumeStage, next: clock(), failure: nil)
            try await store.save(queued, leaseOwner: lease.leaseOwner!)
        } catch {
            try? await store.release(id: draftID, ownerID: context.userID, leaseOwner: lease.leaseOwner!)
            throw error
        }
        try await store.release(id: draftID, ownerID: context.userID, leaseOwner: lease.leaseOwner!)
        await resume(context: context)
        return draftID
    }

    public func resume(context: SessionContext) async {
        while await session.isCurrent(context) {
            guard let rows = try? await store.listPending(ownerID: context.userID) else { return }
            for row in rows where !active.contains(row.id) {
                guard row.state != .draft && row.state != .needsCorrection && row.state != .needsLogin,
                      row.nextAttemptAt.map({ $0 <= clock() }) ?? true,
                      !((row.state == .retryWaiting || row.state == .outcomeUnknown) &&
                        row.nextAttemptAt == nil) else { continue }
                active.insert(row.id)
                await process(id: row.id, context: context)
                active.remove(row.id)
                guard await session.isCurrent(context) else { return }
            }
            guard let remaining = try? await store.listPending(ownerID: context.userID),
                  remaining.count < rows.count else { return }
        }
    }

    public func cancel(operationID: UUID, context: SessionContext) async throws {
        guard await session.isCurrent(context), !active.contains(operationID) else { throw AppFailure.outcomeUnknown }
        let rows = try await store.listPending(ownerID: context.userID)
        guard let row = rows.first(where: { $0.id == operationID }) else { throw AppFailure.notFound }
        guard row.state != .registering && row.state != .outcomeUnknown &&
              !(row.resumeStage == .register && row.attemptCount > 0) else {
            throw AppFailure.outcomeUnknown
        }
        let leaseID = UUID()
        guard let claimed = try await store.claim(id: operationID, ownerID: context.userID,
                                                  leaseOwner: leaseID, leaseExpiresAt: clock().addingTimeInterval(300)) else {
            throw AppFailure.serviceUnavailable
        }
        do {
            try await store.save(try changed(claimed, state: .cancelled, stage: .none,
                                             next: nil, failure: .cancelled), leaseOwner: leaseID)
        } catch {
            try? await store.release(id: operationID, ownerID: context.userID, leaseOwner: leaseID)
            throw error
        }
        try await store.release(id: operationID, ownerID: context.userID, leaseOwner: leaseID)
    }

    private func process(id: UUID, context: SessionContext) async {
        let leaseID = UUID()
        guard let row = try? await store.claim(id: id, ownerID: context.userID,
                                               leaseOwner: leaseID, leaseExpiresAt: clock().addingTimeInterval(300)) else { return }
        await processClaimed(row, leaseID: leaseID, context: context)
        try? await store.release(id: id, ownerID: context.userID, leaseOwner: leaseID)
    }

    private func processClaimed(_ row: PendingSubmission, leaseID: UUID,
                                context: SessionContext) async {
        var current = row
        do {
            try await checkContext(context)
            let payload = try JSONDecoder().decode(SubmissionPayload.self, from: current.payloadData)
            guard matches(payload, kind: current.kind), current.schemaVersion == 1 else {
                throw AppFailure.validation("保存済み投稿の形式が不正です")
            }
            let dependency: UUID?
            if let id = current.dependsOn {
                dependency = try await store.completedRemoteID(for: id, ownerID: context.userID)
                guard dependency != nil else { return }
            } else { dependency = nil }
            let relatedPhotoID: UUID?
            if case let .ar(ar) = payload, let photoOperationID = ar.targetPhotoOperationID {
                relatedPhotoID = try await store.completedRemoteID(for: photoOperationID, ownerID: context.userID)
                guard relatedPhotoID != nil else { return }
            } else { relatedPhotoID = nil }
            try await checkContext(context)
            if current.resumeStage == .upload {
                if current.state != .uploading {
                    current = try changed(current, state: .uploading, stage: .upload,
                                          next: nil, failure: nil, incrementAttempt: true)
                    try await store.save(current, leaseOwner: leaseID)
                }
                try await transport.ensureUploaded(current, payload: payload, context: context)
                try await checkContext(context)
                current = try changed(current, state: .registering, stage: .register,
                                      next: nil, failure: nil)
                try await store.save(current, leaseOwner: leaseID)
            } else {
                if current.state != .registering {
                    current = try changed(current, state: .registering, stage: .register,
                                          next: nil, failure: nil, incrementAttempt: true)
                    try await store.save(current, leaseOwner: leaseID)
                }
            }
            try await checkContext(context)
            let remoteID = try await transport.register(current, payload: payload,
                                                        dependencyRemoteID: dependency,
                                                        relatedPhotoRemoteID: relatedPhotoID,
                                                        context: context)
            try await checkContext(context)
            current = try changed(current, state: .completed, stage: .none,
                                  remoteID: remoteID, next: nil, failure: nil)
            try await store.save(current, leaseOwner: leaseID)
        } catch {
            // register応答の消失はreceiptを再照会する。uploadへ戻さない。
            guard await session.isCurrent(context) else { return }
            let failure = error as? AppFailure ?? .serviceUnavailable
            let state: SubmissionState
            let next: Date?
            switch failure {
            case .needsLogin: state = .needsLogin; next = nil
            case .forbidden, .validation, .notFound: state = .needsCorrection; next = nil
            case .cancelled: state = .cancelled; next = nil
            case .outcomeUnknown:
                state = .outcomeUnknown
                next = current.attemptCount < 5 ? clock().addingTimeInterval(delay(current.attemptCount)) : nil
            default: state = .retryWaiting
                next = current.attemptCount < 5 ? clock().addingTimeInterval(delay(current.attemptCount)) : nil
            }
            // 登録が始まった後の通信断は成功済みの可能性がある。
            let resolvedState = current.resumeStage == .register && state == .retryWaiting ? .outcomeUnknown : state
            if let updated = try? changed(current, state: resolvedState, stage: current.resumeStage,
                                          next: next, failure: failure) {
                try? await store.save(updated, leaseOwner: leaseID)
            }
        }
    }

    private func checkContext(_ context: SessionContext) async throws {
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
    }

    private func changed(_ row: PendingSubmission, state: SubmissionState,
                         stage: SubmissionResumeStage, remoteID: UUID? = nil,
                         next: Date?, failure: AppFailure?, incrementAttempt: Bool = false) throws -> PendingSubmission {
        guard let changed = row.replacingProgress(state: state, resumeStage: stage,
            remoteID: remoteID ?? row.remoteID, attemptCount: row.attemptCount + (incrementAttempt ? 1 : 0),
            nextAttemptAt: next, lastFailure: failure, leaseOwner: row.leaseOwner,
            leaseExpiresAt: row.leaseExpiresAt, updatedAt: max(clock(), row.updatedAt)) else {
            throw AppFailure.validation("投稿状態を更新できません")
        }
        return changed
    }

    private func delay(_ attempts: Int) -> TimeInterval {
        min(60, pow(2, Double(max(1, attempts)))) * Double.random(in: 0.8...1.2)
    }

    private func matches(_ payload: SubmissionPayload, kind: SubmissionKind) -> Bool {
        return switch (payload, kind) {
        case (.photo, .photo), (.rakugaki, .rakugaki), (.ar, .ar), (.groupAnswer, .groupAnswer): true
        default: false
        }
    }
}
