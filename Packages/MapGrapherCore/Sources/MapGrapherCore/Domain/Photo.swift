import Foundation

public struct Photo: Equatable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let title: String
    public let location: GeoPoint
    public let visibility: Visibility
    public let drawPermission: Visibility
    public let requiresApproval: Bool
    public let createdAt: Date
    public let asset: AssetReference
    public let thumbnail: AssetReference?
    public let likeCount: Int
    public let likedByMe: Bool

    public init?(
        id: UUID,
        ownerID: UUID,
        title: String,
        location: GeoPoint,
        visibility: Visibility,
        drawPermission: Visibility,
        requiresApproval: Bool,
        createdAt: Date,
        asset: AssetReference,
        thumbnail: AssetReference?,
        likeCount: Int,
        likedByMe: Bool
    ) {
        guard likeCount >= 0, createdAt.timeIntervalSinceReferenceDate.isFinite else {
            return nil
        }
        self.id = id
        self.ownerID = ownerID
        self.title = title
        self.location = location
        self.visibility = visibility
        self.drawPermission = drawPermission
        self.requiresApproval = requiresApproval
        self.createdAt = createdAt
        self.asset = asset
        self.thumbnail = thumbnail
        self.likeCount = likeCount
        self.likedByMe = likedByMe
    }
}
