import Foundation

public enum ArAnchorType: String, Codable, Sendable {
    case localPlane = "LOCAL_PLANE"
}

public struct ArExperience: Equatable, Sendable {
    public let id: UUID
    public let photoID: UUID
    public let rakugakiID: UUID
    public let asset: AssetReference
    public let unlockRadiusM: Double
    public let discoveryRadiusM: Double
    public let displayWidthM: Double
    public let location: GeoPoint
    public let anchorType: ArAnchorType

    public init?(
        id: UUID,
        photoID: UUID,
        rakugakiID: UUID,
        asset: AssetReference,
        unlockRadiusM: Double,
        discoveryRadiusM: Double,
        displayWidthM: Double,
        location: GeoPoint,
        anchorType: ArAnchorType
    ) {
        guard unlockRadiusM.isFinite,
              discoveryRadiusM.isFinite,
              displayWidthM.isFinite,
              (10.0...200.0).contains(unlockRadiusM),
              (30.0...500.0).contains(discoveryRadiusM),
              discoveryRadiusM >= unlockRadiusM,
              (0.1...10.0).contains(displayWidthM) else {
            return nil
        }
        self.id = id
        self.photoID = photoID
        self.rakugakiID = rakugakiID
        self.asset = asset
        self.unlockRadiusM = unlockRadiusM
        self.discoveryRadiusM = discoveryRadiusM
        self.displayWidthM = displayWidthM
        self.location = location
        self.anchorType = anchorType
    }
}
