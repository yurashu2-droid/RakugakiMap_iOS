import Foundation
import MapGrapherCore

struct ARTrace: Identifiable, Equatable, Sendable {
    let id: UUID
    let photoID: UUID
    let location: GeoPoint
    let unlockRadiusM: Double
    let discoveryRadiusM: Double
    let distanceM: Double
    let createdAt: Date
    let anchorType: ArAnchorType

    init?(id: UUID, photoID: UUID, location: GeoPoint, unlockRadiusM: Double,
          discoveryRadiusM: Double, distanceM: Double, createdAt: Date,
          anchorType: ArAnchorType) {
        guard unlockRadiusM.isFinite, (10...200).contains(unlockRadiusM),
              discoveryRadiusM.isFinite, (30...500).contains(discoveryRadiusM),
              discoveryRadiusM >= unlockRadiusM,
              distanceM.isFinite, distanceM >= 0,
              createdAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        self.id = id; self.photoID = photoID; self.location = location
        self.unlockRadiusM = unlockRadiusM; self.discoveryRadiusM = discoveryRadiusM
        self.distanceM = distanceM; self.createdAt = createdAt; self.anchorType = anchorType
    }
}

@MainActor
protocol ARExperienceServing {
    func experience(photoID: UUID, context: SessionContext) async throws -> ArExperience
    func nearbyTraces(at point: GeoPoint, context: SessionContext) async throws -> [ARTrace]
    func publish(photoID: UUID, rakugakiID: UUID, unlockRadiusM: Double,
                 discoveryRadiusM: Double, displayWidthM: Double,
                 context: SessionContext) async throws -> ArExperience
}

@MainActor
protocol ARRemoteCalling {
    func experience(photoID: UUID) async throws -> [ArExperienceDTO]
    func nearbyTraces(at point: GeoPoint) async throws -> [NearbyArTraceDTO]
    func publish(_ request: CreateArExperienceRequestDTO) async throws -> ArExperienceRowDTO
    func history(photoID: UUID) async throws -> [PendingRakugakiDTO]
}

@MainActor
struct SupabaseARRemote: ARRemoteCalling {
    let gateway: SupabaseGateway

    func experience(photoID: UUID) async throws -> [ArExperienceDTO] {
        try await gateway.rpc("get_ar_experience",
                              parameters: PhotoIDRequestDTO(targetPhotoId: photoID))
    }

    func nearbyTraces(at point: GeoPoint) async throws -> [NearbyArTraceDTO] {
        try await gateway.rpc("get_nearby_ar_traces",
                              parameters: NearbyArTracesRequestDTO(
                                  currentLatitude: point.latitude,
                                  currentLongitude: point.longitude))
    }

    func publish(_ request: CreateArExperienceRequestDTO) async throws -> ArExperienceRowDTO {
        try await gateway.rpc("create_ar_experience", parameters: request)
    }

    func history(photoID: UUID) async throws -> [PendingRakugakiDTO] {
        try await gateway.rpc("history_rakugakis",
                              parameters: PhotoIDRequestDTO(targetPhotoId: photoID))
    }
}

@MainActor
final class ARRepository: ARExperienceServing {
    private let remote: any ARRemoteCalling
    private let photos: any PhotoReading
    private let session: any SessionProviding

    init(remote: any ARRemoteCalling, photos: any PhotoReading,
         session: any SessionProviding) {
        self.remote = remote; self.photos = photos; self.session = session
    }

    convenience init(gateway: SupabaseGateway, photos: any PhotoReading,
                     session: any SessionProviding) {
        self.init(remote: SupabaseARRemote(gateway: gateway), photos: photos, session: session)
    }

    func experience(photoID: UUID, context: SessionContext) async throws -> ArExperience {
        try await check(context)
        let permission = try await photos.permissions(photoID: photoID)
        try await check(context)
        guard permission.canView else { throw AppFailure.forbidden }
        let rows = try await remote.experience(photoID: photoID)
        try await check(context)
        guard rows.count == 1, let row = rows.first,
              row.photoId == photoID else { throw AppFailure.notFound }
        return try Self.map(row)
    }

    func nearbyTraces(at point: GeoPoint, context: SessionContext) async throws -> [ARTrace] {
        try await check(context)
        let rows = try await remote.nearbyTraces(at: point)
        try await check(context)
        return try rows.map { row in
            guard let location = GeoPoint(latitude: row.latitude, longitude: row.longitude),
                  let trace = ARTrace(id: row.id, photoID: row.photoId, location: location,
                    unlockRadiusM: row.unlockRadiusM,
                    discoveryRadiusM: row.discoveryRadiusM,
                    distanceM: row.distanceM, createdAt: row.createdAt,
                    anchorType: row.anchorType) else {
                throw AppFailure.validation("AR痕跡の形式が不正です")
            }
            return trace
        }
    }

    func publish(photoID: UUID, rakugakiID: UUID, unlockRadiusM: Double,
                 discoveryRadiusM: Double, displayWidthM: Double,
                 context: SessionContext) async throws -> ArExperience {
        guard unlockRadiusM.isFinite, (10...200).contains(unlockRadiusM),
              discoveryRadiusM.isFinite, (30...500).contains(discoveryRadiusM),
              discoveryRadiusM >= unlockRadiusM,
              displayWidthM.isFinite, (0.1...10).contains(displayWidthM) else {
            throw AppFailure.validation("AR公開の距離または表示幅が不正です")
        }
        try await check(context)
        let permission = try await photos.permissions(photoID: photoID)
        try await check(context)
        guard permission.isOwner else { throw AppFailure.forbidden }
        let history = try await remote.history(photoID: photoID)
        try await check(context)
        guard history.contains(where: { $0.id == rakugakiID && $0.photoId == photoID &&
            $0.status == .approved }) else { throw AppFailure.validation("承認済みラクガキが必要です") }
        let row = try await remote.publish(CreateArExperienceRequestDTO(
            targetPhotoId: photoID, targetRakugakiId: rakugakiID,
            targetUnlockRadiusM: unlockRadiusM, targetDiscoveryRadiusM: discoveryRadiusM,
            targetDisplayWidthM: displayWidthM))
        try await check(context)
        guard row.photoId == photoID, row.rakugakiId == rakugakiID,
              row.status == "READY" else { throw AppFailure.validation("AR公開が完了していません") }
        return try await experience(photoID: photoID, context: context)
    }

    private func check(_ context: SessionContext) async throws {
        try Task.checkCancellation()
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
    }

    private static func map(_ row: ArExperienceDTO) throws -> ArExperience {
        guard let location = GeoPoint(latitude: row.latitude, longitude: row.longitude),
              let asset = AssetReference(bucket: "rakugakis", path: row.assetPath),
              let experience = ArExperience(id: row.id, photoID: row.photoId,
                  rakugakiID: row.rakugakiId, asset: asset,
                  unlockRadiusM: row.unlockRadiusM,
                  discoveryRadiusM: row.discoveryRadiusM,
                  displayWidthM: row.displayWidthM, location: location,
                  anchorType: row.anchorType) else {
            throw AppFailure.validation("AR体験の形式が不正です")
        }
        return experience
    }
}
