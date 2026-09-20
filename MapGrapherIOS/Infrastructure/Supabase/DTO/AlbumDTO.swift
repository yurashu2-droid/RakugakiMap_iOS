import Foundation

struct AlbumDTO: Decodable, Sendable {
    let id: UUID
    let ownerId: UUID
    let title: String
    let description: String?
    let createdAt: Date
}
struct AlbumPhotoDTO: Decodable, Sendable {
    let albumId: UUID
    let photoId: UUID
    let addedAt: Date
}
