import Foundation
import MapGrapherCore

struct CreateRakugakiRequestDTO: Encodable, Sendable {
    let targetPhotoId: UUID
    let targetAssetPath: String
}
struct CreateRakugakiV2RequestDTO: Encodable, Sendable {
    let clientRequestId: UUID
    let targetPhotoId: UUID
    let targetAssetPath: String
}
struct ApproveRakugakiRequestDTO: Encodable, Sendable {
    let targetRakugakiId: UUID
    let approved: Bool
}
struct RakugakiRowDTO: Decodable, Sendable {
    let id: UUID
    let photoId: UUID
    let authorId: UUID
    let assetPath: String
    let status: ApprovalStatus
    let createdAt: Date?
    let updatedAt: Date?
}
struct PendingRakugakiDTO: Decodable, Sendable {
    let id: UUID
    let photoId: UUID
    let authorId: UUID
    let authorName: String?
    let authorAvatarPath: String?
    let assetPath: String
    let status: ApprovalStatus
    let createdAt: Date?
}
