import Foundation
import MapGrapherCore
import Supabase

/// 非冪等ないいね操作を写真単位で直列化し、設定・削除はDBのowner判定を通す。
@MainActor
final class SupabasePhotoDetailService: PhotoDetailUIService {
    let dataMode: SocialUIDataMode = .live

    private let gateway: SupabaseGateway
    private let session: any SessionProviding
    private let assetLoader: PrivateAssetLoader
    private var likesInFlight: Set<UUID> = []

    init(gateway: SupabaseGateway, session: any SessionProviding,
         assetLoader: PrivateAssetLoader) {
        self.gateway = gateway
        self.session = session
        self.assetLoader = assetLoader
    }

    func toggleLike(photoID: UUID, liked: Bool) async throws -> PhotoLikeState {
        guard !likesInFlight.contains(photoID) else { throw PhotoDetailUIError.serviceUnavailable }
        let context = try await requireContext()
        likesInFlight.insert(photoID)
        defer { likesInFlight.remove(photoID) }
        // 通信結果が失われた場合の再toggleは意図を反転させるため行わない。
        let rows: [LikeResultDTO] = try await gateway.rpc(
            "toggle_like", parameters: PhotoIDRequestDTO(targetPhotoId: photoID))
        try await check(context)
        guard rows.count == 1, let row = rows.first,
              row.likeCount >= 0,
              row.likeCount <= Int64(Int.max) else {
            throw PhotoDetailUIError.serviceUnavailable
        }
        // 別端末で状態が変わっていても、再toggleせずサーバーの確定状態を返す。
        return PhotoLikeState(isLiked: row.liked, likeCount: Int(row.likeCount))
    }

    func updatePhotoSettings(photoID: UUID, visibility: Visibility,
                             drawPermission: Visibility,
                             requiresApproval: Bool) async throws -> PhotoSettingsSnapshot {
        let context = try await requireContext()
        let row: PhotoRowDTO = try await gateway.rpc("update_photo_settings",
            parameters: UpdatePhotoSettingsRequestDTO(
                targetPhotoId: photoID, newPrivacy: visibility,
                newDrawPermission: drawPermission,
                newRequiresApproval: requiresApproval))
        try await check(context)
        guard row.id == photoID, row.ownerId == context.userID,
              row.privacy == visibility, row.drawPermission == drawPermission,
              row.requiresApproval == requiresApproval else {
            throw PhotoDetailUIError.serviceUnavailable
        }
        await assetLoader.invalidate(context: context)
        return PhotoSettingsSnapshot(visibility: visibility,
                                     drawPermission: drawPermission,
                                     requiresApproval: requiresApproval)
    }

    func deletePhoto(photoID: UUID) async throws {
        let context = try await requireContext()
        try await gateway.rpcVoid("delete_photo",
            parameters: PhotoIDRequestDTO(targetPhotoId: photoID))
        try await check(context)
        await assetLoader.invalidate(context: context)
    }

    private func requireContext() async throws -> SessionContext {
        guard let context = await session.currentContext() else {
            throw PhotoDetailUIError.permissionDenied
        }
        return context
    }

    private func check(_ context: SessionContext) async throws {
        guard await session.isCurrent(context) else {
            throw PhotoDetailUIError.permissionDenied
        }
    }
}
