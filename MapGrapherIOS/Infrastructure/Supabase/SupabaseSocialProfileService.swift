import Foundation
import MapGrapherCore
import Supabase

/// RLSを通した結果だけを画面へ渡す。通信失敗を空配列や0件へ変換しない。
@MainActor
final class SupabaseSocialProfileService: SocialProfileUIService {
    let dataMode: SocialUIDataMode = .live

    private let gateway: SupabaseGateway
    private let session: any SessionProviding

    init(gateway: SupabaseGateway, session: any SessionProviding) {
        self.gateway = gateway
        self.session = session
    }

    func acceptedFriends() async throws -> [FriendRelation] {
        let context = try await requireContext()
        let rows: [FriendRelationDTO] = try await gateway.rpc("accepted_friends", parameters: EmptyRPC())
        try await check(context)
        return try rows.map { row in
            guard row.status == "ACCEPTED", let name = row.friendName,
                  let uniqueID = row.friendUniqueId else { throw SocialUIError.serviceUnavailable }
            return FriendRelation(id: row.id, friendID: row.friendId, friendName: name,
                                  friendUniqueID: uniqueID, status: .accepted)
        }
    }

    func pendingFriendRequests() async throws -> [FriendRequest] {
        let context = try await requireContext()
        let rows: [FriendRelationDTO] = try await gateway.rpc("pending_friend_requests",
                                                              parameters: EmptyRPC())
        try await check(context)
        let metadata: [FriendRequestTimeDTO] = try await gateway.client.from("friend_requests")
            .select("id,created_at").eq("addressee_id", value: context.userID.uuidString)
            .eq("status", value: "PENDING").execute().value
        try await check(context)
        let times = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0.createdAt) })
        return try rows.map { row in
            guard row.status == "PENDING", let name = row.friendName,
                  let uniqueID = row.friendUniqueId, let createdAt = times[row.id] else {
                throw SocialUIError.serviceUnavailable
            }
            return FriendRequest(id: row.id, requesterID: row.friendId,
                                 requesterName: name, requesterUniqueID: uniqueID,
                                 createdAt: createdAt)
        }
    }

    func requestFriend(uniqueID: String) async throws -> FriendRequest {
        let context = try await requireContext()
        let normalized = uniqueID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 40 else { throw SocialUIError.invalidInput }
        let row: FriendRequestRowDTO = try await gateway.rpc("request_friend",
            parameters: RequestFriendRequestDTO(targetUserUniqueId: normalized))
        try await check(context)
        guard row.requesterId == context.userID, row.status == "PENDING",
              let createdAt = row.createdAt else { throw SocialUIError.serviceUnavailable }
        let profile = try await currentProfile(context: context)
        guard let profile else { throw SocialUIError.serviceUnavailable }
        return FriendRequest(id: row.id, requesterID: context.userID,
                             requesterName: profile.displayName,
                             requesterUniqueID: profile.userUniqueID, createdAt: createdAt)
    }

    func respondFriendRequest(id: UUID, accepted: Bool) async throws {
        let context = try await requireContext()
        let row: FriendRequestRowDTO = try await gateway.rpc("respond_friend_request",
            parameters: RespondFriendRequestDTO(targetRequestId: id, accepted: accepted))
        try await check(context)
        guard row.id == id, row.addresseeId == context.userID,
              row.status == (accepted ? "ACCEPTED" : "REJECTED") else {
            throw SocialUIError.serviceUnavailable
        }
    }

    func removeFriend(id: UUID) async throws {
        let context = try await requireContext()
        try await gateway.client.rpc("remove_friend",
            params: RemoveFriendRequestDTO(targetRequestId: id)).execute()
        try await check(context)
    }

    func currentProfile() async throws -> UserProfile? {
        let context = try await requireContext()
        return try await currentProfile(context: context)
    }

    func updateProfile(displayName: String) async throws -> UserProfile {
        let context = try await requireContext()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw SocialUIError.invalidInput }
        let rows: [ProfileDTO] = try await gateway.client.from("profiles")
            .update(["display_name": name], returning: .representation)
            .eq("id", value: context.userID.uuidString).execute().value
        try await check(context)
        guard rows.count == 1, let row = rows.first, row.id == context.userID else {
            throw SocialUIError.serviceUnavailable
        }
        return Self.profile(row)
    }

    func stampCardStats() async throws -> StampCardStats? {
        _ = try await requireContext()
        // 現行APIに統計契約はない。未取得を0件と表示しない。
        return nil
    }

    func pendingRakugakis() async throws -> [RakugakiHistoryItem] {
        let context = try await requireContext()
        let titles = try await ownedPhotoTitles(context: context)
        let rows: [PendingRakugakiDTO] = try await gateway.rpc("pending_rakugakis",
                                                                 parameters: EmptyRPC())
        try await check(context)
        return try rows.map { try Self.historyItem($0, titles: titles, canModerate: true,
                                                   expected: .pending) }
    }

    func historyRakugakis() async throws -> [RakugakiHistoryItem] {
        let context = try await requireContext()
        let titles = try await ownedPhotoTitles(context: context)
        var items: [RakugakiHistoryItem] = []
        for photoID in titles.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let rows: [PendingRakugakiDTO] = try await gateway.rpc("history_rakugakis",
                parameters: PhotoIDRequestDTO(targetPhotoId: photoID))
            try await check(context)
            items += try rows.map { try Self.historyItem($0, titles: titles,
                                                         canModerate: true, expected: .approved) }
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func approveRakugaki(id: UUID, approved: Bool) async throws -> RakugakiHistoryItem {
        let context = try await requireContext()
        let row: RakugakiRowDTO = try await gateway.rpc("approve_rakugaki",
            parameters: ApproveRakugakiRequestDTO(targetRakugakiId: id, approved: approved))
        try await check(context)
        guard row.id == id, row.status == (approved ? .approved : .rejected),
              let createdAt = row.createdAt else { throw SocialUIError.serviceUnavailable }
        let titles = try await ownedPhotoTitles(context: context)
        guard let title = titles[row.photoId] else { throw SocialUIError.permissionDenied }
        let authors: [ProfileDTO] = try await gateway.client.from("profiles")
            .select("id,user_unique_id,display_name,avatar_path")
            .eq("id", value: row.authorId.uuidString).execute().value
        try await check(context)
        guard authors.count == 1, let author = authors.first else {
            throw SocialUIError.serviceUnavailable
        }
        return RakugakiHistoryItem(id: row.id, photoID: row.photoId,
                                   photoTitle: title, authorName: author.displayName,
                                   assetPath: row.assetPath, status: row.status,
                                   createdAt: createdAt, canModerate: false)
    }

    func albums() async throws -> [AlbumSummary] {
        let context = try await requireContext()
        let rows: [AlbumDTO] = try await gateway.client.from("albums")
            .select("id,owner_id,title,description,created_at")
            .eq("owner_id", value: context.userID.uuidString).execute().value
        try await check(context)
        var result: [AlbumSummary] = []
        for row in rows {
            guard row.ownerId == context.userID else { throw SocialUIError.permissionDenied }
            let visiblePhotos = try await albumPhotos(albumID: row.id, context: context)
            result.append(AlbumSummary(id: row.id, title: row.title,
                                       description: row.description ?? "", createdAt: row.createdAt,
                                       photoCount: visiblePhotos.count))
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    func createAlbum(title: String, description: String) async throws -> AlbumSummary {
        let context = try await requireContext()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, description.count <= 500 else {
            throw SocialUIError.invalidInput
        }
        let rows: [AlbumDTO] = try await gateway.client.from("albums")
            .insert(AlbumCreateDTO(ownerId: context.userID, title: name,
                                   description: description), returning: .representation)
            .execute().value
        try await check(context)
        guard rows.count == 1, let row = rows.first, row.ownerId == context.userID else {
            throw SocialUIError.serviceUnavailable
        }
        return AlbumSummary(id: row.id, title: row.title, description: row.description ?? "",
                            createdAt: row.createdAt, photoCount: 0)
    }

    func albumPhotos(albumID: UUID) async throws -> [AlbumPhoto] {
        let context = try await requireContext()
        return try await albumPhotos(albumID: albumID, context: context)
    }

    func addPhoto(photoID: UUID, to albumID: UUID) async throws -> AlbumPhoto {
        let context = try await requireContext()
        try await requireOwnedAlbum(albumID, context: context)
        let rows: [AlbumPhotoDTO] = try await gateway.client.from("album_photos")
            .insert(AlbumPhotoLinkDTO(albumId: albumID, photoId: photoID),
                    returning: .representation).execute().value
        try await check(context)
        guard rows.count == 1, let row = rows.first,
              row.albumId == albumID, row.photoId == photoID else {
            throw SocialUIError.serviceUnavailable
        }
        let photo = try await visiblePhoto(photoID, context: context)
        return AlbumPhoto(id: photoID, photoID: photoID, title: photo.title, addedAt: row.addedAt)
    }

    func removePhoto(photoID: UUID, from albumID: UUID) async throws {
        let context = try await requireContext()
        try await requireOwnedAlbum(albumID, context: context)
        let rows: [AlbumPhotoDTO] = try await gateway.client.from("album_photos")
            .delete(returning: .representation)
            .eq("album_id", value: albumID.uuidString)
            .eq("photo_id", value: photoID.uuidString).execute().value
        try await check(context)
        guard rows.count == 1, rows[0].albumId == albumID,
              rows[0].photoId == photoID else { throw SocialUIError.notFound }
    }

    func deleteAlbum(id: UUID) async throws {
        let context = try await requireContext()
        let rows: [AlbumDTO] = try await gateway.client.from("albums")
            .delete(returning: .representation).eq("id", value: id.uuidString)
            .eq("owner_id", value: context.userID.uuidString).execute().value
        try await check(context)
        guard rows.count == 1, rows[0].id == id else { throw SocialUIError.notFound }
    }

    private func currentProfile(context: SessionContext) async throws -> UserProfile? {
        let rows: [ProfileDTO] = try await gateway.client.from("profiles")
            .select("id,user_unique_id,display_name,avatar_path")
            .eq("id", value: context.userID.uuidString).execute().value
        try await check(context)
        guard rows.count <= 1 else { throw SocialUIError.serviceUnavailable }
        return rows.first.map(Self.profile)
    }

    private func ownedPhotoTitles(context: SessionContext) async throws -> [UUID: String] {
        let rows: [OwnedPhotoDTO] = try await gateway.client.from("photos")
            .select("id,title").eq("owner_id", value: context.userID.uuidString)
            .execute().value
        try await check(context)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.title) })
    }

    private func albumPhotos(albumID: UUID, context: SessionContext) async throws -> [AlbumPhoto] {
        try await requireOwnedAlbum(albumID, context: context)
        let links: [AlbumPhotoDTO] = try await gateway.client.from("album_photos")
            .select("album_id,photo_id,added_at")
            .eq("album_id", value: albumID.uuidString).execute().value
        try await check(context)
        var result: [AlbumPhoto] = []
        for link in links {
            guard link.albumId == albumID else { throw SocialUIError.serviceUnavailable }
            // リンクのRLSだけでは写真の現在の閲覧権限を保証しない。
            guard let photo = try await optionalVisiblePhoto(link.photoId, context: context) else {
                continue
            }
            result.append(AlbumPhoto(id: link.photoId, photoID: link.photoId,
                                     title: photo.title, addedAt: link.addedAt))
        }
        return result.sorted { $0.addedAt > $1.addedAt }
    }

    private func requireOwnedAlbum(_ id: UUID, context: SessionContext) async throws {
        let rows: [AlbumDTO] = try await gateway.client.from("albums")
            .select("id,owner_id,title,description,created_at")
            .eq("id", value: id.uuidString).eq("owner_id", value: context.userID.uuidString)
            .execute().value
        try await check(context)
        guard rows.count == 1, rows[0].ownerId == context.userID else {
            throw SocialUIError.notFound
        }
    }

    private func visiblePhoto(_ id: UUID, context: SessionContext) async throws -> OwnedPhotoDTO {
        guard let photo = try await optionalVisiblePhoto(id, context: context) else {
            throw SocialUIError.permissionDenied
        }
        return photo
    }

    private func optionalVisiblePhoto(_ id: UUID, context: SessionContext) async throws -> OwnedPhotoDTO? {
        let rows: [OwnedPhotoDTO] = try await gateway.client.from("photos")
            .select("id,title").eq("id", value: id.uuidString).execute().value
        try await check(context)
        guard rows.count <= 1 else { throw SocialUIError.serviceUnavailable }
        return rows.first
    }

    private func requireContext() async throws -> SessionContext {
        guard let context = await session.currentContext() else { throw SocialUIError.permissionDenied }
        return context
    }

    private func check(_ context: SessionContext) async throws {
        guard await session.isCurrent(context) else { throw SocialUIError.permissionDenied }
    }

    private static func profile(_ row: ProfileDTO) -> UserProfile {
        UserProfile(id: row.id, userUniqueID: row.userUniqueId,
                    displayName: row.displayName, avatarPath: row.avatarPath)
    }

    private static func historyItem(_ row: PendingRakugakiDTO, titles: [UUID: String],
                                    canModerate: Bool, expected: ApprovalStatus) throws -> RakugakiHistoryItem {
        guard row.status == expected, let title = titles[row.photoId],
              let name = row.authorName, let date = row.createdAt else {
            throw SocialUIError.serviceUnavailable
        }
        return RakugakiHistoryItem(id: row.id, photoID: row.photoId,
                                   photoTitle: title, authorName: name,
                                   assetPath: row.assetPath, status: row.status,
                                   createdAt: date, canModerate: canModerate)
    }
}

private struct EmptyRPC: Encodable, Sendable {}
private struct FriendRequestTimeDTO: Decodable, Sendable {
    let id: UUID
    let createdAt: Date
}
private struct OwnedPhotoDTO: Decodable, Sendable {
    let id: UUID
    let title: String
}
private struct AlbumCreateDTO: Encodable, Sendable {
    let ownerId: UUID
    let title: String
    let description: String
}
private struct AlbumPhotoLinkDTO: Encodable, Sendable {
    let albumId: UUID
    let photoId: UUID
}
