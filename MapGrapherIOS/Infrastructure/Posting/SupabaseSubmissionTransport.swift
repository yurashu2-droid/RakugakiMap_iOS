import CryptoKit
import Foundation
import MapGrapherCore
import Supabase

/// B01が適用済みの環境でのみ使用する投稿adapter。
@MainActor
final class SupabaseSubmissionTransport: SubmissionTransport {
    private let gateway: SupabaseGateway
    private let session: any SessionProviding
    private let files: DraftFileStore

    init(gateway: SupabaseGateway, session: any SessionProviding,
         files: DraftFileStore) {
        self.gateway = gateway; self.session = session; self.files = files
    }

    func ensureUploaded(_ submission: PendingSubmission, payload: SubmissionPayload,
                        context: SessionContext) async throws {
        guard await session.isCurrent(context), submission.ownerID == context.userID else {
            throw AppFailure.needsLogin
        }
        let expected: (bucket: String, mime: String, size: Int64, hash: String)
        switch payload {
        case .photo(let p): expected = ("photos", p.mimeType, p.byteSize, p.sha256)
        case .rakugaki(let p): expected = ("rakugakis", p.mimeType, p.byteSize, p.sha256)
        case .ar, .groupAnswer: return
        }
        guard submission.assetPaths.count == 1, submission.localFilePaths.count == 1,
              let asset = submission.assetPaths.first, asset.bucket == expected.bucket,
              asset.path.hasPrefix("\(context.userID.uuidString.lowercased())/\(expected.bucket)/"),
              let local = submission.localFilePaths.first,
              expected.size > 0, expected.hash.count == 64 else {
            throw AppFailure.validation("投稿画像の参照が不正です")
        }
        let url = URL(fileURLWithPath: local)
        let data: Data
        do {
            data = try files.read(url, ownerID: context.userID, operationID: submission.id)
        } catch {
            throw AppFailure.validation("保存済みの投稿画像を読めません")
        }
        guard Int64(data.count) == expected.size,
              Self.digest(data) == expected.hash else {
            throw AppFailure.validation("投稿画像の内容が変化しました")
        }
        let storage = gateway.client.storage.from(asset.bucket)
        do {
            let exists = try await storage.exists(path: asset.path)
            guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
            if exists {
                try await verifyStoredObject(bucket: asset.bucket, path: asset.path,
                                             mime: expected.mime, size: expected.size,
                                             sha256: expected.hash, context: context)
                guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
                return
            }
            try await storage.upload(asset.path, fileURL: url,
                                     options: FileOptions(contentType: expected.mime, upsert: false))
        } catch {
            // upload応答だけ失われた場合も、同じpathの実体を確認する。
            guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
            let exists = (try? await storage.exists(path: asset.path)) == true
            guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
            if exists {
                try await verifyStoredObject(bucket: asset.bucket, path: asset.path,
                                             mime: expected.mime, size: expected.size,
                                             sha256: expected.hash, context: context)
                guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
                return
            }
            throw Self.map(error)
        }
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        try await verifyStoredObject(bucket: asset.bucket, path: asset.path,
                                     mime: expected.mime, size: expected.size,
                                     sha256: expected.hash, context: context)
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
    }

    func register(_ submission: PendingSubmission, payload: SubmissionPayload,
                  dependencyRemoteID: UUID?, relatedPhotoRemoteID: UUID?,
                  context: SessionContext) async throws -> UUID {
        guard await session.isCurrent(context), submission.ownerID == context.userID else {
            throw AppFailure.needsLogin
        }
        do {
            let remoteID: UUID
            switch payload {
            case .photo(let p):
                guard submission.assetPaths.count == 1, let asset = submission.assetPaths.first,
                      asset.bucket == "photos" else { throw AppFailure.validation("写真pathが不正です") }
                let row: PhotoRowDTO = try await gateway.rpc("create_photo_pin_v2", parameters:
                    CreatePhotoPinV2RequestDTO(clientRequestId: submission.id, title: p.title,
                        lat: p.point.latitude, lon: p.point.longitude, privacy: p.privacy,
                        drawPermission: p.drawPermission, requiresApproval: p.requiresApproval,
                        photoPath: asset.path, mimeType: p.mimeType, byteSize: p.byteSize))
                remoteID = row.id
            case .rakugaki(let p):
                guard submission.assetPaths.count == 1, let asset = submission.assetPaths.first,
                      asset.bucket == "rakugakis", let photoID = p.targetPhotoID ?? dependencyRemoteID else {
                    throw AppFailure.validation("ラクガキの写真IDまたはpathが不正です")
                }
                let row: RakugakiRowDTO = try await gateway.rpc("create_rakugaki_v2", parameters:
                    CreateRakugakiV2RequestDTO(clientRequestId: submission.id,
                                               targetPhotoId: photoID, targetAssetPath: asset.path))
                remoteID = row.id
            case .ar(let p):
                guard let photoID = p.targetPhotoID ?? relatedPhotoRemoteID,
                      let rakugakiID = p.targetRakugakiID ?? dependencyRemoteID else {
                    throw AppFailure.validation("ARの依存投稿が未完了です")
                }
                let row: ArExperienceRowDTO = try await gateway.rpc("create_ar_experience", parameters:
                    CreateArExperienceRequestDTO(targetPhotoId: photoID, targetRakugakiId: rakugakiID,
                        targetUnlockRadiusM: p.unlockRadiusM, targetDiscoveryRadiusM: p.discoveryRadiusM,
                        targetDisplayWidthM: p.displayWidthM))
                remoteID = row.id
            case .groupAnswer(let p):
                guard let photoID = p.targetPhotoID ?? dependencyRemoteID else {
                    throw AppFailure.validation("グループ回答の写真が未完了です")
                }
                let row: GroupAnswerRowDTO = try await gateway.rpc("submit_group_answer", parameters:
                    SubmitGroupAnswerRequestDTO(targetMissionId: p.missionID, targetPhotoId: photoID))
                remoteID = row.id
            }
            guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
            return remoteID
        } catch {
            throw Self.map(error)
        }
    }

    private func verifyStoredObject(bucket: String, path: String,
                                    mime: String, size: Int64, sha256: String,
                                    context: SessionContext) async throws {
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        let storage = gateway.client.storage.from(bucket)
        let info = try await storage.info(path: path)
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        guard info.bucketId == bucket, info.size.map(Int64.init) == size,
              info.contentType?.lowercased() == mime.lowercased() else {
            throw AppFailure.validation("Storage上の画像情報が下書きと一致しません")
        }
        let data = try await storage.download(path: path)
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        guard Int64(data.count) == size, Self.digest(data) == sha256 else {
            throw AppFailure.validation("Storage上の画像内容が下書きと一致しません")
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func map(_ error: Error) -> AppFailure {
        if let known = error as? AppFailure { return known }
        if error is CancellationError { return .cancelled }
        if let storage = error as? StorageError {
            switch storage.statusCode {
            case "401": return .needsLogin
            case "403": return .forbidden
            case "404": return .notFound
            case "429": return .rateLimited
            default: return .serviceUnavailable
            }
        }
        if let postgrest = error as? PostgrestError {
            if postgrest.code == "PGRST301" || postgrest.message.localizedCaseInsensitiveContains("jwt") {
                return .needsLogin
            }
            if postgrest.code == "42501" { return .forbidden }
            if postgrest.message.contains("REQUEST_CONFLICT") {
                return .validation("同じ投稿IDの入力が一致しません")
            }
            if postgrest.message.contains("STORAGE_INVALID") ||
                postgrest.message.contains("DRAW_FORBIDDEN") {
                return .validation("投稿の画像または権限を確認してください")
            }
        }
        if error is URLError { return .offline }
        return .outcomeUnknown
    }
}
