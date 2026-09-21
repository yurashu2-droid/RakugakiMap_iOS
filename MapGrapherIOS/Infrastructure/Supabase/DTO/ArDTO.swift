import Foundation
import MapGrapherCore

struct CreateArExperienceRequestDTO: Encodable, Sendable {
    let targetPhotoId: UUID
    let targetRakugakiId: UUID
    let targetUnlockRadiusM: Double
    let targetDiscoveryRadiusM: Double
    let targetDisplayWidthM: Double
}
struct PublishPersistentARRequestDTO: Encodable, Sendable {
    let targetPhotoId: UUID
    let targetRakugakiId: UUID
    let targetWorldMapPath: String
    let targetAnchorName: String
    let targetUnlockRadiusM: Double
    let targetDiscoveryRadiusM: Double
    let targetDisplayWidthM: Double
    let targetFallbackAltitudeM: Double?
    let targetFallbackHeadingDeg: Double?
}
struct ArExperienceRowDTO: Decodable, Sendable {
    let id: UUID
    let photoId: UUID
    let rakugakiId: UUID
    let status: String
    let assetPath: String
    let unlockRadiusM: Double
    let discoveryRadiusM: Double
    let displayWidthM: Double
}
struct ArExperienceDTO: Decodable, Sendable {
    let id: UUID
    let photoId: UUID
    let rakugakiId: UUID
    let anchorType: ArAnchorType
    let assetPath: String
    let unlockRadiusM: Double
    let discoveryRadiusM: Double
    let displayWidthM: Double
    let latitude: Double
    let longitude: Double
    let worldMapPath: String?
    let anchorName: String?
    let fallbackAltitudeM: Double?
    let fallbackHeadingDeg: Double?
    let worldMapFormatVersion: Int?
}
struct NearbyArTracesRequestDTO: Encodable, Sendable {
    let currentLatitude: Double
    let currentLongitude: Double
}
struct NearbyArTraceDTO: Decodable, Sendable {
    let id: UUID
    let photoId: UUID
    let anchorType: ArAnchorType
    let unlockRadiusM: Double
    let discoveryRadiusM: Double
    let latitude: Double
    let longitude: Double
    let distanceM: Double
    let createdAt: Date
}
