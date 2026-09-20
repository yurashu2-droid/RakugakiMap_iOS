import Foundation

struct RequestFriendRequestDTO: Encodable, Sendable { let targetUserUniqueId: String }
struct RespondFriendRequestDTO: Encodable, Sendable {
    let targetRequestId: UUID
    let accepted: Bool
}
struct RemoveFriendRequestDTO: Encodable, Sendable { let targetRequestId: UUID }
struct AcceptedFriendIDDTO: Decodable, Sendable { let friendId: UUID }
struct FriendRelationDTO: Decodable, Sendable {
    let id: UUID
    let friendId: UUID
    let friendName: String?
    let friendUniqueId: String?
    let friendAvatarPath: String?
    let status: String
}
struct FriendRequestRowDTO: Decodable, Sendable {
    let id: UUID
    let requesterId: UUID?
    let addresseeId: UUID?
    let status: String?
    let createdAt: Date?
}
