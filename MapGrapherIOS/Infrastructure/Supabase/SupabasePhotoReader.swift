import Foundation
import MapGrapherCore

/// 地図画面へ、RLS適用済みの写真だけをドメイン値として渡します。
@MainActor
final class SupabasePhotoReader: PhotoReading {
    private let gateway: SupabaseGateway
    private let session: any SessionProviding

    init(gateway: SupabaseGateway, session: any SessionProviding) {
        self.gateway = gateway
        self.session = session
    }

    func nearby(center: GeoPoint, radiusM: Double) async throws -> [Photo] {
        guard radiusM.isFinite, radiusM > 0, radiusM <= 10_000 else {
            throw PhotoReadingError.unknown
        }
        guard let context = await session.currentContext() else {
            throw PhotoReadingError.permissionDenied
        }
        do {
            let rows: [NearbyPhotoDTO] = try await gateway.rpc(
                "nearby_photos",
                parameters: NearbyPhotosRequestDTO(lat: center.latitude,
                                                    lon: center.longitude,
                                                    radiusMeters: radiusM)
            )
            guard await session.isCurrent(context) else { throw AppFailure.cancelled }
            return try rows.map(Self.map)
        } catch {
            throw Self.mapError(error)
        }
    }

    func permissions(photoID: UUID) async throws -> PhotoPermissions {
        guard let context = await session.currentContext() else {
            throw PhotoReadingError.permissionDenied
        }
        do {
            let rows: [PhotoPermissionDTO] = try await gateway.rpc(
                "photo_permissions", parameters: PhotoIDRequestDTO(targetPhotoId: photoID)
            )
            guard await session.isCurrent(context) else { throw AppFailure.cancelled }
            guard rows.count == 1, let row = rows.first else {
                throw rows.isEmpty ? PhotoReadingError.notFound : PhotoReadingError.unknown
            }
            return PhotoPermissions(canView: row.canView, canDraw: row.canDraw, isOwner: row.isOwner)
        } catch {
            throw Self.mapError(error)
        }
    }

    static func map(_ row: NearbyPhotoDTO) throws -> Photo {
        guard let latitude = row.latitude, let longitude = row.longitude,
              let location = GeoPoint(latitude: latitude, longitude: longitude),
              let privacy = row.privacy, let drawPermission = row.drawPermission,
              let createdAt = row.createdAt, let photoPath = row.photoPath,
              let asset = AssetReference(bucket: "photos", path: photoPath),
              let likeCount = row.likeCount, likeCount >= 0, likeCount <= Int64(Int.max),
              let photo = Photo(id: row.id, ownerID: row.ownerId,
                                title: row.title ?? "", location: location,
                                visibility: privacy, drawPermission: drawPermission,
                                requiresApproval: row.requiresApproval ?? false,
                                createdAt: createdAt, asset: asset,
                                thumbnail: row.thumbnailPath.flatMap {
                                    AssetReference(bucket: "photos", path: $0)
                                }, likeCount: Int(likeCount),
                                likedByMe: row.likedByMe ?? false) else {
            throw PhotoReadingError.unknown
        }
        return photo
    }

    private static func mapError(_ error: Error) -> PhotoReadingError {
        if let known = error as? PhotoReadingError { return known }
        if let failure = error as? AppFailure {
            switch failure {
            case .offline: return .offline
            case .forbidden, .needsLogin, .cancelled: return .permissionDenied
            case .notFound: return .notFound
            case .serviceUnavailable, .rateLimited: return .serviceUnavailable
            default: return .unknown
            }
        }
        if error is URLError { return .offline }
        return .unknown
    }
}
