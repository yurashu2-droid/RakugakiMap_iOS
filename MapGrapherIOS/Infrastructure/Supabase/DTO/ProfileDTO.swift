import Foundation

struct ProfileDTO: Codable, Sendable {
    let id: UUID
    let userUniqueId: String
    let displayName: String
    let avatarPath: String?
}
struct ProfileUpsertDTO: Encodable, Sendable {
    let id: UUID
    let userUniqueId: String
    let displayName: String
    let avatarPath: String?
}
