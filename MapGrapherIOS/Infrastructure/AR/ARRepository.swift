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
    func publishPersistent(package: PersistentARPackage, photoID: UUID, rakugakiID: UUID,
                           unlockRadiusM: Double, discoveryRadiusM: Double,
                           fallbackAltitudeM: Double?, fallbackHeadingDeg: Double?,
                           context: SessionContext) async throws -> ArExperience
}

extension ARExperienceServing {
    func publishPersistent(package: PersistentARPackage, photoID: UUID, rakugakiID: UUID,
                           unlockRadiusM: Double, discoveryRadiusM: Double,
                           fallbackAltitudeM: Double?, fallbackHeadingDeg: Double?,
                           context: SessionContext) async throws -> ArExperience {
        throw AppFailure.serviceUnavailable
    }
}

@MainActor
protocol ARRemoteCalling {
    func experience(photoID: UUID) async throws -> [ArExperienceDTO]
    func nearbyTraces(at point: GeoPoint) async throws -> [NearbyArTraceDTO]
    func publish(_ request: CreateArExperienceRequestDTO) async throws -> ArExperienceRowDTO
    func publishPersistent(_ request: PublishPersistentARRequestDTO) async throws -> ArExperienceRowDTO
    func history(photoID: UUID) async throws -> [PendingRakugakiDTO]
}

extension ARRemoteCalling {
    func publishPersistent(_ request: PublishPersistentARRequestDTO) async throws -> ArExperienceRowDTO {
        throw AppFailure.serviceUnavailable
    }
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

    func publishPersistent(_ request: PublishPersistentARRequestDTO) async throws -> ArExperienceRowDTO {
        try await gateway.rpc("publish_persistent_ar_experience", parameters: request)
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
    private let worldMaps: any ARWorldMapStoring

    init(remote: any ARRemoteCalling, photos: any PhotoReading,
         session: any SessionProviding,
         worldMaps: any ARWorldMapStoring = makeUnavailableARWorldMapStore()) {
        self.remote = remote; self.photos = photos; self.session = session
        self.worldMaps = worldMaps
    }

    convenience init(gateway: SupabaseGateway, photos: any PhotoReading,
                     session: any SessionProviding) {
        self.init(remote: SupabaseARRemote(gateway: gateway), photos: photos, session: session,
                  worldMaps: ARWorldMapStore(gateway: gateway, session: session))
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

    func publishPersistent(package: PersistentARPackage, photoID: UUID, rakugakiID: UUID,
                           unlockRadiusM: Double, discoveryRadiusM: Double,
                           fallbackAltitudeM: Double?, fallbackHeadingDeg: Double?,
                           context: SessionContext) async throws -> ArExperience {
        guard package.formatVersion == PersistentARPackage.formatVersion,
              package.displayWidthM.isFinite, (0.1...10).contains(package.displayWidthM),
              unlockRadiusM.isFinite, (10...200).contains(unlockRadiusM),
              discoveryRadiusM.isFinite, (30...500).contains(discoveryRadiusM),
              discoveryRadiusM >= unlockRadiusM,
              fallbackAltitudeM?.isFinite != false,
              fallbackHeadingDeg?.isFinite != false,
              fallbackHeadingDeg.map({ (0.0..<360.0).contains($0) }) != false else {
            throw AppFailure.validation("永続ARの公開値が不正です")
        }
        try await check(context)
        let permission = try await photos.permissions(photoID: photoID)
        try await check(context)
        guard permission.isOwner else { throw AppFailure.forbidden }
        let history = try await remote.history(photoID: photoID)
        try await check(context)
        guard history.contains(where: { $0.id == rakugakiID && $0.photoId == photoID &&
            $0.status == .approved }) else { throw AppFailure.validation("承認済みラクガキが必要です") }

        let uploaded = try await worldMaps.upload(package: package, context: context)
        do {
            let row = try await remote.publishPersistent(PublishPersistentARRequestDTO(
                targetPhotoId: photoID, targetRakugakiId: rakugakiID,
                targetWorldMapPath: uploaded.path, targetAnchorName: package.anchorName,
                targetUnlockRadiusM: unlockRadiusM,
                targetDiscoveryRadiusM: discoveryRadiusM,
                targetDisplayWidthM: package.displayWidthM,
                targetFallbackAltitudeM: fallbackAltitudeM,
                targetFallbackHeadingDeg: fallbackHeadingDeg))
            try await check(context)
            guard row.photoId == photoID, row.rakugakiId == rakugakiID,
                  row.status == "READY" else {
                throw AppFailure.validation("永続ARの公開が完了していません")
            }
        } catch {
            try? await worldMaps.delete(asset: uploaded, context: context)
            throw error
        }
        return try await experience(photoID: photoID, context: context)
    }

    private func check(_ context: SessionContext) async throws {
        try Task.checkCancellation()
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
    }

    static func mapForTesting(_ row: ArExperienceDTO) throws -> ArExperience { try map(row) }

    private static func map(_ row: ArExperienceDTO) throws -> ArExperience {
        let worldMap: AssetReference?
        switch row.anchorType {
        case .localPlane:
            guard row.worldMapPath == nil, row.anchorName == nil,
                  row.worldMapFormatVersion == nil else {
                throw AppFailure.validation("従来ARに不要なワールドマップ情報があります")
            }
            worldMap = nil
        case .worldMapV1:
            guard let path = row.worldMapPath,
                  let reference = AssetReference(bucket: "ar-world-maps", path: path),
                  row.anchorName != nil, row.worldMapFormatVersion == 1 else {
                throw AppFailure.validation("永続ARのワールドマップ情報が不足しています")
            }
            worldMap = reference
        }
        guard let location = GeoPoint(latitude: row.latitude, longitude: row.longitude),
              let asset = AssetReference(bucket: "rakugakis", path: row.assetPath),
              let experience = ArExperience(id: row.id, photoID: row.photoId,
                  rakugakiID: row.rakugakiId, asset: asset,
                  unlockRadiusM: row.unlockRadiusM,
                  discoveryRadiusM: row.discoveryRadiusM,
                  displayWidthM: row.displayWidthM, location: location,
                  anchorType: row.anchorType, worldMap: worldMap,
                  anchorName: row.anchorName,
                  worldMapFormatVersion: row.worldMapFormatVersion,
                  fallbackAltitudeM: row.fallbackAltitudeM,
                  fallbackHeadingDeg: row.fallbackHeadingDeg) else {
            throw AppFailure.validation("AR体験の形式が不正です")
        }
        return experience
    }
}
