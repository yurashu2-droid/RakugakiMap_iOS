import CryptoKit
import Foundation
import MapGrapherCore

/// 画面の下書きを、所有者別のファイルと永続キューへ固定する。
@MainActor
final class RealPostingUIService: PostingUIService {
    // 編集可能な下書きを画面へ復元する導線は未接続。保存と再送キューは永続化する。
    let storesDraftsPersistently = false

    private let fixedContext: SessionContext
    private let session: any SessionProviding
    private let store: any SubmissionStoring
    private let coordinator: SubmissionCoordinator
    private let files: DraftFileStore
    private let imagePreparer: ImagePreparer
    private let drawingExporter: DrawingExporter
    private let location: any MapLocationProviding
    private var savedPayloads: [UUID: Data] = [:]
    private var savedShape: [UUID: (hasDrawing: Bool, missionID: UUID?)] = [:]
    private var savedRows: [UUID: PendingSubmission] = [:]
    private var preparedImages: [UUID: String] = [:]

    init(context: SessionContext, session: any SessionProviding, store: any SubmissionStoring,
         coordinator: SubmissionCoordinator, files: DraftFileStore,
         imagePreparer: ImagePreparer, drawingExporter: DrawingExporter,
         location: any MapLocationProviding) {
        self.fixedContext = context; self.session = session
        self.store = store; self.coordinator = coordinator
        self.files = files; self.imagePreparer = imagePreparer
        self.drawingExporter = drawingExporter; self.location = location
    }

    func prepareImage(data: Data, suggestedFilename: String) async throws -> PreparedPostingImage {
        guard await session.isCurrent(fixedContext) else {
            throw PostingServiceError.permissionDenied
        }
        guard !data.isEmpty else { throw PostingServiceError.invalidImage }
        guard data.count <= 20 * 1024 * 1024 else { throw PostingServiceError.imageTooLarge }
        // 元画像は一時ファイルだけに置き、ImagePreparerでメタデータを除いたJPEGへ再符号化する。
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent("posting-input-\(UUID().uuidString).tmp")
        do {
            try data.write(to: input, options: .atomic)
            defer { try? FileManager.default.removeItem(at: input) }
            let prepared = try await imagePreparer.prepare(input: input)
            guard await session.isCurrent(fixedContext) else {
                try? FileManager.default.removeItem(at: prepared.fileURL)
                throw PostingServiceError.permissionDenied
            }
            let preview = try Data(contentsOf: prepared.fileURL)
            guard await session.isCurrent(fixedContext) else {
                try? FileManager.default.removeItem(at: prepared.fileURL)
                throw PostingServiceError.permissionDenied
            }
            let result = PreparedPostingImage(prepared: prepared, previewData: preview)
            preparedImages[result.id] = prepared.sha256
            return result
        } catch let error as PostingServiceError {
            throw error
        } catch let error as ImagePreparationError {
            switch error {
            case .invalidImage, .metadataRemovalFailed: throw PostingServiceError.invalidImage
            case .dimensionsTooLarge: throw PostingServiceError.dimensionsTooLarge
            case .outputTooLarge: throw PostingServiceError.imageTooLarge
            case .outputFailed: throw PostingServiceError.outputFailed
            }
        } catch {
            throw PostingServiceError.outputFailed
        }
    }

    func currentLocation() async -> GeoPoint? {
        guard await session.isCurrent(fixedContext) else { return nil }
        let state = await location.requestCurrentLocation()
        guard await session.isCurrent(fixedContext) else { return nil }
        if case let .ready(point) = state { return point }
        return nil
    }

    func saveDraft(_ draft: PostingDraft) async throws {
        guard await session.isCurrent(fixedContext) else {
            throw PostingServiceError.permissionDenied
        }
        let context = fixedContext
        guard let postingImage = draft.preparedImage,
              let image = draft.preparedImage?.prepared,
              preparedImages[postingImage.id] == image.sha256,
              let point = draft.location,
              image.mimeType == "image/jpeg",
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.title.count <= 100,
              draft.createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PostingServiceError.invalidDraft
        }
        // 半径などの選択値がUIに無いため、AR予約を暗黙に成功させない。
        guard !draft.reserveAR else { throw PostingServiceError.invalidDraft }
        if let previous = savedShape[draft.id],
           previous.hasDrawing != draft.hasDrawing || previous.missionID != draft.missionID {
            throw PostingServiceError.invalidDraft
        }
        if let drawing = draft.drawing, !drawing.strokes.isEmpty,
           (drawing.pixelWidth != image.pixelWidth || drawing.pixelHeight != image.pixelHeight) {
            throw PostingServiceError.invalidDraft
        }
        let owner = context.userID
        let photoPayload = SubmissionPayload.photo(.init(
            title: draft.title, point: point, privacy: draft.visibility,
            drawPermission: draft.drawPermission, requiresApproval: draft.requiresApproval,
            mimeType: image.mimeType, byteSize: image.byteSize, sha256: image.sha256))
        let photoData = try JSONEncoder().encode(photoPayload)
        if let previous = savedPayloads[draft.id], previous != photoData {
            throw PostingServiceError.invalidDraft
        }
        let photoFile = try persist(image, owner: owner, operation: draft.id,
                                    fileName: "\(draft.id.uuidString.lowercased()).jpg")
        let photoPath = "\(owner.uuidString.lowercased())/photos/\(draft.id.uuidString.lowercased()).jpg"
        guard let photoAsset = AssetReference(bucket: "photos", path: photoPath),
              let photo = PendingSubmission(id: draft.id, ownerID: owner, schemaVersion: 1,
                  kind: .photo, payloadData: photoData, localFilePaths: [photoFile.path],
                  assetPaths: [photoAsset], dependsOn: nil, remoteID: nil, state: .draft,
                  resumeStage: .upload, attemptCount: 0, nextAttemptAt: nil, lastFailure: nil,
                  leaseOwner: nil, leaseExpiresAt: nil, createdAt: draft.createdAt,
                  updatedAt: max(Date(), draft.createdAt)) else {
            throw PostingServiceError.invalidDraft
        }
        try await insertIfMissing(photo, context: context)
        savedPayloads[draft.id] = photoData
        savedShape[draft.id] = (draft.hasDrawing, draft.missionID)

        if let drawing = draft.drawing, !drawing.strokes.isEmpty {
            guard await session.isCurrent(context) else { throw PostingServiceError.permissionDenied }
            let drawingID = Self.childID(parent: draft.id, purpose: "rakugaki")
            let exported = try await drawingExporter.export(document: drawing)
            guard await session.isCurrent(context) else { throw PostingServiceError.permissionDenied }
            let file = try persist(exported, owner: owner, operation: drawingID,
                                   fileName: "\(drawingID.uuidString.lowercased()).png")
            let path = "\(owner.uuidString.lowercased())/rakugakis/\(drawingID.uuidString.lowercased()).png"
            let payload = SubmissionPayload.rakugaki(.init(targetPhotoID: nil,
                mimeType: exported.mimeType, byteSize: exported.byteSize, sha256: exported.sha256))
            guard let asset = AssetReference(bucket: "rakugakis", path: path),
                  let row = PendingSubmission(id: drawingID, ownerID: owner, schemaVersion: 1,
                    kind: .rakugaki, payloadData: try JSONEncoder().encode(payload),
                    localFilePaths: [file.path], assetPaths: [asset], dependsOn: draft.id,
                    remoteID: nil, state: .draft, resumeStage: .upload, attemptCount: 0,
                    nextAttemptAt: nil, lastFailure: nil, leaseOwner: nil, leaseExpiresAt: nil,
                    createdAt: draft.createdAt, updatedAt: max(Date(), draft.createdAt)) else {
                throw PostingServiceError.invalidDraft
            }
            try await insertIfMissing(row, context: context)
        }

        if let missionID = draft.missionID {
            let answerID = Self.childID(parent: draft.id, purpose: "group-answer")
            let payload = SubmissionPayload.groupAnswer(.init(missionID: missionID,
                                                               targetPhotoID: nil))
            guard let row = PendingSubmission(id: answerID, ownerID: owner, schemaVersion: 1,
                kind: .groupAnswer, payloadData: try JSONEncoder().encode(payload),
                localFilePaths: [], assetPaths: [], dependsOn: draft.id,
                remoteID: nil, state: .draft, resumeStage: .register, attemptCount: 0,
                nextAttemptAt: nil, lastFailure: nil, leaseOwner: nil, leaseExpiresAt: nil,
                createdAt: draft.createdAt, updatedAt: max(Date(), draft.createdAt)) else {
                throw PostingServiceError.invalidDraft
            }
            try await insertIfMissing(row, context: context)
        }
        guard await session.isCurrent(context) else { throw PostingServiceError.permissionDenied }
    }

    func submit(_ draft: PostingDraft) async throws -> PostingSubmissionResult {
        guard !draft.reserveAR else { throw PostingServiceError.invalidDraft }
        guard await session.isCurrent(fixedContext) else {
            throw PostingServiceError.permissionDenied
        }
        let context = fixedContext
        let pending = try await store.listPending(ownerID: context.userID)
        let photoID = try await store.completedRemoteID(for: draft.id, ownerID: context.userID)
        guard photoID != nil || pending.contains(where: { $0.id == draft.id }) else {
            throw PostingServiceError.invalidDraft
        }
        if let photo = pending.first(where: { $0.id == draft.id }),
           photo.state == .draft || photo.state == .retryWaiting ||
           photo.state == .needsLogin || photo.state == .outcomeUnknown {
            try await coordinator.enqueue(draftID: draft.id, context: context)
        } else {
            await coordinator.resume(context: context)
        }
        for childID in childIDs(for: draft) {
            let rows = try await store.listPending(ownerID: context.userID)
            if let child = rows.first(where: { $0.id == childID }), child.state == .draft {
                try await coordinator.enqueue(draftID: childID, context: context)
            }
        }
        guard await session.isCurrent(context) else { throw PostingServiceError.permissionDenied }
        let remotePhotoID = try await store.completedRemoteID(for: draft.id, ownerID: context.userID)
        let remaining = try await store.listPending(ownerID: context.userID)
        let operationIDs = [draft.id] + childIDs(for: draft)
        for id in operationIDs {
            if remaining.contains(where: { $0.id == id }) { continue }
            guard try await store.completedRemoteID(for: id, ownerID: context.userID) != nil else {
                throw PostingServiceError.serviceUnavailable
            }
        }
        let active = operationIDs.compactMap { id in remaining.first(where: { $0.id == id }) }
        guard await session.isCurrent(context) else { throw PostingServiceError.permissionDenied }
        if let first = active.first {
            return PostingSubmissionResult(draftID: draft.id, state: first.state,
                                           remotePhotoID: remotePhotoID)
        }
        return PostingSubmissionResult(draftID: draft.id, state: .completed,
                                       remotePhotoID: remotePhotoID)
    }

    private func insertIfMissing(_ row: PendingSubmission, context: SessionContext) async throws {
        guard await session.isCurrent(context) else { throw PostingServiceError.permissionDenied }
        let pending = try await store.listPending(ownerID: context.userID)
        if let existing = pending.first(where: { $0.id == row.id }) {
            guard Self.sameImmutableInput(existing, row) else {
                throw PostingServiceError.invalidDraft
            }
            savedRows[row.id] = row
            return
        }
        // 完了済み操作を同じIDで作り直さない。再開はCoordinatorのreceipt経路だけ。
        if try await store.completedRemoteID(for: row.id, ownerID: context.userID) != nil {
            guard let previous = savedRows[row.id], Self.sameImmutableInput(previous, row) else {
                throw PostingServiceError.invalidDraft
            }
            return
        }
        guard await session.isCurrent(context) else { throw PostingServiceError.permissionDenied }
        try await store.insertDraft(row)
        savedRows[row.id] = row
    }

    private func persist(_ image: PreparedImage, owner: UUID,
                         operation: UUID, fileName: String) throws -> URL {
        let data = try Data(contentsOf: image.fileURL)
        guard Int64(data.count) == image.byteSize,
              Self.digest(data) == image.sha256 else { throw PostingServiceError.invalidImage }
        let target = files.rootURL.appendingPathComponent(owner.uuidString)
            .appendingPathComponent(operation.uuidString).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: target.path) {
            let previous = try files.read(target, ownerID: owner, operationID: operation)
            guard previous == data else { throw PostingServiceError.invalidDraft }
            return target
        }
        return try files.save(data, ownerID: owner, operationID: operation, fileName: fileName)
    }

    private func childIDs(for draft: PostingDraft) -> [UUID] {
        var ids: [UUID] = []
        if draft.hasDrawing { ids.append(Self.childID(parent: draft.id, purpose: "rakugaki")) }
        if draft.missionID != nil { ids.append(Self.childID(parent: draft.id, purpose: "group-answer")) }
        return ids
    }

    private static func sameImmutableInput(_ lhs: PendingSubmission,
                                           _ rhs: PendingSubmission) -> Bool {
        lhs.id == rhs.id && lhs.ownerID == rhs.ownerID && lhs.schemaVersion == rhs.schemaVersion &&
            lhs.kind == rhs.kind && lhs.payloadData == rhs.payloadData &&
            lhs.localFilePaths == rhs.localFilePaths && lhs.assetPaths == rhs.assetPaths &&
            lhs.dependsOn == rhs.dependsOn && lhs.createdAt == rhs.createdAt
    }

    private static func childID(parent: UUID, purpose: String) -> UUID {
        let hash = digest(Data("\(parent.uuidString):\(purpose)".utf8))
        let id = "\(hash.prefix(8))-\(hash.dropFirst(8).prefix(4))-4\(hash.dropFirst(13).prefix(3))-a\(hash.dropFirst(17).prefix(3))-\(hash.dropFirst(20).prefix(12))"
        return UUID(uuidString: id)!
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
