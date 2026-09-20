import Foundation

public enum Visibility: String, Codable, Sendable {
    case anyone = "ANYONE"
    case friends = "FRIENDS"
    case onlyMe = "ONLY_ME"
}

public enum ApprovalStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

public struct GeoPoint: Equatable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        guard let point = Self(latitude: latitude, longitude: longitude) else {
            throw DecodingError.dataCorruptedError(
                forKey: .latitude,
                in: container,
                debugDescription: "緯度または経度が有効範囲外です"
            )
        }
        self = point
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

public struct SessionContext: Equatable, Sendable {
    public let userID: UUID
    public let epoch: UUID

    public init(userID: UUID, epoch: UUID) {
        self.userID = userID
        self.epoch = epoch
    }
}

public struct LocationSample: Equatable, Sendable {
    public let point: GeoPoint
    public let horizontalAccuracyM: Double
    public let timestamp: Date

    public init?(point: GeoPoint, horizontalAccuracyM: Double, timestamp: Date) {
        guard horizontalAccuracyM.isFinite,
              horizontalAccuracyM >= 0,
              timestamp.timeIntervalSinceReferenceDate.isFinite else {
            return nil
        }
        self.point = point
        self.horizontalAccuracyM = horizontalAccuracyM
        self.timestamp = timestamp
    }
}

public struct PhotoPermissions: Equatable, Sendable {
    public let canView: Bool
    public let canDraw: Bool
    public let isOwner: Bool

    public init(canView: Bool, canDraw: Bool, isOwner: Bool) {
        self.canView = canView
        self.canDraw = canDraw
        self.isOwner = isOwner
    }
}
