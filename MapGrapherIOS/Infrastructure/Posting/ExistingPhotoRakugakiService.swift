import CryptoKit
import Foundation
import MapGrapherCore
import Supabase
import UIKit

@MainActor
protocol RakugakiBaseImageLoading {
    func load(asset: AssetReference, context: SessionContext) async throws -> UIImage
}

@MainActor
struct PrivateRakugakiBaseImageLoader: RakugakiBaseImageLoading {
    let loader: PrivateAssetLoader
    func load(asset: AssetReference, context: SessionContext) async throws -> UIImage {
        try await loader.load(asset: asset,
                              targetPixelSize: CGSize(width: 4_096, height: 4_096),
                              context: context)
    }
}

@MainActor
protocol RakugakiApprovalReading {
    func status(rakugakiID: UUID, photoID: UUID,
                context: SessionContext) async throws -> ApprovalStatus?
}

/// 作者本人に対するrakugakis SELECT RLSで、投稿後のPENDING/APPROVEDを確認する。
@MainActor
struct SupabaseRakugakiApprovalReader: RakugakiApprovalReading {
    let gateway: SupabaseGateway
    let session: any SessionProviding

    func status(rakugakiID: UUID, photoID: UUID,
                context: SessionContext) async throws -> ApprovalStatus? {
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
        let rows = try await gateway.existingRakugakiRow(id: rakugakiID)
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
        guard let row = rows.first else { return nil }
        guard row.id == rakugakiID, row.photoId == photoID,
              row.authorId == context.userID else {
            throw AppFailure.validation("ラクガキの投稿結果が一致しません")
        }
        return row.status
    }
}

// SDK応答を画面アクターへ渡さず、Sendableな行だけを返す。
extension SupabaseGateway {
    func existingRakugakiRow(id: UUID) async throws -> [RakugakiRowDTO] {
        try await client.from("rakugakis")
            .select("id,photo_id,author_id,asset_path,status,created_at,updated_at")
            .eq("id", value: id.uuidString).execute().value
    }
}

struct ExistingRakugakiSubmissionResult: Sendable {
    let operationID: UUID
    let state: SubmissionState
    let remoteRakugakiID: UUID?
    let approval: ApprovalStatus?
}

@MainActor
protocol ExistingPhotoRakugakiServing {
    func prepare(photo: Photo) async throws -> PreparedPostingImage
    func submit(photo: Photo, base: PreparedPostingImage,
                document: DrawingDocument, operationID: UUID) async throws
        -> ExistingRakugakiSubmissionResult
    func discard(base: PreparedPostingImage)
}

/// 元写真をアップロードせず、透明PNGだけを既存写真IDへ紐付ける。
@MainActor
final class ExistingPhotoRakugakiService: ExistingPhotoRakugakiServing {
    private let fixedContext: SessionContext
    private let session: any SessionProviding
    private let permissions: any PhotoReading
    private let imageLoader: any RakugakiBaseImageLoading
    private let store: any SubmissionStoring
    private let coordinator: SubmissionCoordinator
    private let files: DraftFileStore
    private let exporter: DrawingExporter
    private let approvalReader: any RakugakiApprovalReading
    private var preparedBases: [UUID: (photoID: UUID, hash: String)] = [:]
    private var savedDocuments: [UUID: String] = [:]

    init(context: SessionContext, session: any SessionProviding,
         permissions: any PhotoReading, imageLoader: any RakugakiBaseImageLoading,
         store: any SubmissionStoring, coordinator: SubmissionCoordinator,
         files: DraftFileStore, exporter: DrawingExporter,
         approvalReader: any RakugakiApprovalReading) {
        fixedContext = context; self.session = session
        self.permissions = permissions; self.imageLoader = imageLoader
        self.store = store; self.coordinator = coordinator
        self.files = files; self.exporter = exporter
        self.approvalReader = approvalReader
    }

    func prepare(photo: Photo) async throws -> PreparedPostingImage {
        try await check()
        try await requireDrawPermission(photoID: photo.id)
        let image = try await imageLoader.load(asset: photo.asset, context: fixedContext)
        try await check()
        guard let cgImage = image.cgImage,
              cgImage.width <= 4_096, cgImage.height <= 4_096,
              let data = image.jpegData(compressionQuality: 0.85),
              !data.isEmpty, data.count <= 20 * 1024 * 1024 else {
            throw AppFailure.validation("元写真を描画用に開けません")
        }
        // UIImageはデコード済みピクセルなので、元写真のEXIFや位置情報を引き継がない。
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("rakugaki-base-\(UUID().uuidString).jpg")
        try data.write(to: file, options: .atomic)
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path)
            try await check()
            let hash = Self.digest(data)
            guard let prepared = PreparedImage(fileURL: file, mimeType: "image/jpeg",
                byteSize: Int64(data.count), pixelWidth: cgImage.width,
                pixelHeight: cgImage.height, sha256: hash) else {
                throw AppFailure.validation("描画用写真が不正です")
            }
            let base = PreparedPostingImage(prepared: prepared, previewData: data)
            preparedBases[base.id] = (photo.id, hash)
            return base
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    func submit(photo: Photo, base: PreparedPostingImage,
                document: DrawingDocument, operationID: UUID) async throws
        -> ExistingRakugakiSubmissionResult {
        try await check()
        guard let prepared = preparedBases[base.id],
              prepared.photoID == photo.id,
              prepared.hash == base.prepared.sha256,
              document.pixelWidth == base.prepared.pixelWidth,
              document.pixelHeight == base.prepared.pixelHeight,
              !document.strokes.isEmpty else {
            throw AppFailure.validation("描画の対象写真または内容が不正です")
        }
        try await requireDrawPermission(photoID: photo.id)
        let documentHash = Self.digest(try JSONEncoder().encode(document))
        if let saved = savedDocuments[operationID], saved != documentHash {
            throw AppFailure.validation("同じ投稿IDの描画内容が変わりました")
        }
        let owner = fixedContext.userID
        let pending = try await store.listPending(ownerID: owner)
        try await check()
        if let existing = pending.first(where: { $0.id == operationID }) {
            guard savedDocuments[operationID] == documentHash,
                  try Self.matches(existing, photoID: photo.id) else {
                throw AppFailure.validation("保存済みの描画と一致しません")
            }
        } else if try await store.completedRemoteID(for: operationID, ownerID: owner) != nil {
            guard savedDocuments[operationID] == documentHash else {
                throw AppFailure.validation("完了済み投稿の再作成はできません")
            }
        } else {
            let exported = try await exporter.export(document: document)
            defer { try? FileManager.default.removeItem(at: exported.fileURL) }
            try await check()
            let data = try Data(contentsOf: exported.fileURL)
            guard exported.mimeType == "image/png", Int64(data.count) == exported.byteSize,
                  Self.digest(data) == exported.sha256 else {
                throw AppFailure.validation("透明PNGの内容が不正です")
            }
            let fileName = operationID.uuidString.lowercased() + ".png"
            let target = files.rootURL.appendingPathComponent(owner.uuidString)
                .appendingPathComponent(operationID.uuidString)
                .appendingPathComponent(fileName)
            let local: URL
            if FileManager.default.fileExists(atPath: target.path) {
                let previous = try files.read(target, ownerID: owner,
                                              operationID: operationID)
                guard previous == data else {
                    throw AppFailure.validation("保存済みのラクガキ画像が異なります")
                }
                local = target
            } else {
                local = try files.save(data, ownerID: owner,
                                       operationID: operationID, fileName: fileName)
            }
            let path = "\(owner.uuidString.lowercased())/rakugakis/\(fileName)"
            guard let asset = AssetReference(bucket: "rakugakis", path: path),
                  let row = PendingSubmission(id: operationID, ownerID: owner,
                    schemaVersion: 1, kind: .rakugaki,
                    payloadData: try JSONEncoder().encode(SubmissionPayload.rakugaki(.init(
                        targetPhotoID: photo.id, mimeType: exported.mimeType,
                        byteSize: exported.byteSize, sha256: exported.sha256))),
                    localFilePaths: [local.path], assetPaths: [asset],
                    dependsOn: nil, remoteID: nil, state: .draft, resumeStage: .upload,
                    attemptCount: 0, nextAttemptAt: nil, lastFailure: nil,
                    leaseOwner: nil, leaseExpiresAt: nil,
                    createdAt: Date(), updatedAt: Date()) else {
                throw AppFailure.validation("ラクガキの下書きが不正です")
            }
            try await check()
            try await store.insertDraft(row)
            savedDocuments[operationID] = documentHash
        }
        try await check()
        let rows = try await store.listPending(ownerID: owner)
        if let row = rows.first(where: { $0.id == operationID }) {
            switch row.state {
            case .draft, .retryWaiting, .needsLogin, .outcomeUnknown:
                try await coordinator.enqueue(draftID: operationID, context: fixedContext)
            case .needsCorrection, .cancelled:
                break
            default:
                await coordinator.resume(context: fixedContext)
            }
        }
        try await check()
        if let remoteID = try await store.completedRemoteID(for: operationID, ownerID: owner) {
            let approval: ApprovalStatus?
            do {
                approval = try await approvalReader.status(rakugakiID: remoteID,
                    photoID: photo.id, context: fixedContext)
            } catch {
                try await check()
                return ExistingRakugakiSubmissionResult(operationID: operationID,
                    state: .outcomeUnknown, remoteRakugakiID: remoteID, approval: nil)
            }
            try await check()
            return ExistingRakugakiSubmissionResult(operationID: operationID,
                state: approval == nil ? .needsCorrection : .completed,
                remoteRakugakiID: remoteID, approval: approval)
        }
        let remaining = try await store.listPending(ownerID: owner)
        try await check()
        guard let current = remaining.first(where: { $0.id == operationID }) else {
            throw AppFailure.serviceUnavailable
        }
        return ExistingRakugakiSubmissionResult(operationID: operationID,
            state: current.state, remoteRakugakiID: nil, approval: nil)
    }

    func discard(base: PreparedPostingImage) {
        guard preparedBases.removeValue(forKey: base.id) != nil else { return }
        try? FileManager.default.removeItem(at: base.prepared.fileURL)
    }

    private func requireDrawPermission(photoID: UUID) async throws {
        let access = try await permissions.permissions(photoID: photoID)
        try await check()
        guard access.canView, access.canDraw else { throw AppFailure.forbidden }
    }

    private func check() async throws {
        try Task.checkCancellation()
        guard await session.isCurrent(fixedContext) else { throw AppFailure.cancelled }
    }

    private static func matches(_ row: PendingSubmission, photoID: UUID) throws -> Bool {
        guard row.kind == .rakugaki, row.dependsOn == nil else { return false }
        let decoded = try JSONDecoder().decode(SubmissionPayload.self, from: row.payloadData)
        guard case .rakugaki(let payload) = decoded else { return false }
        return payload.targetPhotoID == photoID
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
