import Foundation

public enum ArAnchorType: String, Codable, Sendable {
    case localPlane = "LOCAL_PLANE"
    case worldMapV1 = "WORLD_MAP_V1"
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
    public let worldMap: AssetReference?
    public let anchorName: String?
    public let worldMapFormatVersion: Int?
    public let fallbackAltitudeM: Double?
    public let fallbackHeadingDeg: Double?

    public init?(
        id: UUID,
        photoID: UUID,
        rakugakiID: UUID,
        asset: AssetReference,
        unlockRadiusM: Double,
        discoveryRadiusM: Double,
        displayWidthM: Double,
        location: GeoPoint,
        anchorType: ArAnchorType,
        worldMap: AssetReference? = nil,
        anchorName: String? = nil,
        worldMapFormatVersion: Int? = nil,
        fallbackAltitudeM: Double? = nil,
        fallbackHeadingDeg: Double? = nil
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
        switch anchorType {
        case .localPlane:
            guard worldMap == nil, anchorName == nil, worldMapFormatVersion == nil,
                  fallbackAltitudeM == nil, fallbackHeadingDeg == nil else { return nil }
        case .worldMapV1:
            guard worldMap?.bucket == "ar-world-maps",
                  let anchorName,
                  anchorName.hasPrefix("rakugaki:"),
                  UUID(uuidString: String(anchorName.dropFirst("rakugaki:".count))) != nil,
                  worldMapFormatVersion == 1,
                  fallbackAltitudeM?.isFinite != false,
                  fallbackHeadingDeg?.isFinite != false,
                  fallbackHeadingDeg.map({ (0.0..<360.0).contains($0) }) != false else { return nil }
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
        self.worldMap = worldMap
        self.anchorName = anchorName
        self.worldMapFormatVersion = worldMapFormatVersion
        self.fallbackAltitudeM = fallbackAltitudeM
        self.fallbackHeadingDeg = fallbackHeadingDeg
    }
}
