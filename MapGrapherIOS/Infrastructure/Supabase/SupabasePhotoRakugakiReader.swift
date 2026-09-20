import Foundation
import MapGrapherCore

/// 既存の閲覧権限付きRPCから承認済みのラクガキだけを取得する。
@MainActor
final class SupabasePhotoRakugakiReader: PhotoRakugakiReading {
    private let gateway: SupabaseGateway
    private let session: any SessionProviding

    init(gateway: SupabaseGateway, session: any SessionProviding) {
        self.gateway = gateway
        self.session = session
    }

    func approved(photoID: UUID) async throws -> [PhotoRakugaki] {
        guard let context = await session.currentContext() else { throw AppFailure.needsLogin }
        let rows: [PendingRakugakiDTO] = try await gateway.rpc(
            "history_rakugakis", parameters: PhotoIDRequestDTO(targetPhotoId: photoID)
        )
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
        return try rows.map { try Self.map($0, photoID: photoID) }
    }

    static func map(_ row: PendingRakugakiDTO, photoID: UUID) throws -> PhotoRakugaki {
        guard row.photoId == photoID, row.status == .approved,
              let createdAt = row.createdAt,
              let asset = AssetReference(bucket: "rakugakis", path: row.assetPath) else {
            throw AppFailure.serviceUnavailable
        }
        return PhotoRakugaki(id: row.id, authorName: row.authorName ?? "ユーザー",
                             createdAt: createdAt, asset: asset)
    }
}
