import Foundation
import MapGrapherCore

enum SocialUIDataMode: Sendable, Equatable {
    case fake
    case live
}

enum SocialUIError: Error, Equatable, Sendable {
    case offline
    case permissionDenied
    case notFound
    case invalidInput
    case serviceUnavailable
    case operationFailed
}

struct UserProfile: Identifiable, Equatable, Sendable {
    let id: UUID
    let userUniqueID: String
    let displayName: String
    let avatarPath: String?

    init(
        id: UUID,
        userUniqueID: String,
        displayName: String,
        avatarPath: String? = nil
    ) {
        self.id = id
        self.userUniqueID = userUniqueID
        self.displayName = displayName
        self.avatarPath = avatarPath
    }
}

enum FriendRelationStatus: String, Equatable, Sendable {
    case accepted
    case pending
    case rejected
    case unknown
}

struct FriendRelation: Identifiable, Equatable, Sendable {
    let id: UUID
    let friendID: UUID
    let friendName: String
    let friendUniqueID: String
    let status: FriendRelationStatus
}

struct FriendRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let requesterID: UUID
    let requesterName: String
    let requesterUniqueID: String
    let createdAt: Date
}

struct RakugakiHistoryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let photoID: UUID
    let photoTitle: String
    let authorName: String
    let assetPath: String
    let status: ApprovalStatus
    let createdAt: Date
    let canModerate: Bool
}

struct AlbumSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let description: String
    let createdAt: Date
    let photoCount: Int
}

struct AlbumPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let photoID: UUID
    let title: String
    let addedAt: Date
}

struct StampCardStats: Equatable, Sendable {
    let earned: Int
    let total: Int

    init?(earned: Int, total: Int) {
        guard earned >= 0, total >= 0, earned <= total else { return nil }
        self.earned = earned
        self.total = total
    }
}

@MainActor
protocol FriendsUIService {
    func acceptedFriends() async throws -> [FriendRelation]
    func pendingFriendRequests() async throws -> [FriendRequest]
    func requestFriend(uniqueID: String) async throws -> FriendRequest
    func respondFriendRequest(id: UUID, accepted: Bool) async throws
    func removeFriend(id: UUID) async throws
}

@MainActor
protocol ProfileUIService {
    func currentProfile() async throws -> UserProfile?
    func updateProfile(displayName: String) async throws -> UserProfile
    func stampCardStats() async throws -> StampCardStats?
}

@MainActor
protocol RakugakiHistoryUIService {
    /// `pending_rakugakis` の本人写真に対する承認待ちだけを返す。
    func pendingRakugakis() async throws -> [RakugakiHistoryItem]
    /// 本人が所有する写真ごとに `history_rakugakis(target_photo_id)` を取得し、
    /// APPROVED の履歴だけをまとめて返す。
    func historyRakugakis() async throws -> [RakugakiHistoryItem]
    func approveRakugaki(id: UUID, approved: Bool) async throws -> RakugakiHistoryItem
}

@MainActor
protocol AlbumsUIService {
    func albums() async throws -> [AlbumSummary]
    func createAlbum(title: String, description: String) async throws -> AlbumSummary
    func albumPhotos(albumID: UUID) async throws -> [AlbumPhoto]
    func addPhoto(photoID: UUID, to albumID: UUID) async throws -> AlbumPhoto
    func removePhoto(photoID: UUID, from albumID: UUID) async throws
    func deleteAlbum(id: UUID) async throws
}

@MainActor
protocol SocialProfileUIService: FriendsUIService, ProfileUIService,
    RakugakiHistoryUIService, AlbumsUIService {
    var dataMode: SocialUIDataMode { get }
}

@MainActor
final class FakeSocialProfileUIService: SocialProfileUIService {
    let dataMode: SocialUIDataMode = .fake

    var profileValue: UserProfile?
    var stampStats: StampCardStats?
    private(set) var friendsValue: [FriendRelation]
    private(set) var pendingRequests: [FriendRequest]
    private(set) var historyValue: [RakugakiHistoryItem]
    private(set) var albumValues: [AlbumSummary]
    private var photosByAlbum: [UUID: [AlbumPhoto]]

    init(
        profile: UserProfile? = FakeSocialProfileUIService.defaultProfile,
        friends: [FriendRelation] = FakeSocialProfileUIService.defaultFriends,
        pendingRequests: [FriendRequest] = FakeSocialProfileUIService.defaultRequests,
        history: [RakugakiHistoryItem] = FakeSocialProfileUIService.defaultHistory,
        albums: [AlbumSummary] = FakeSocialProfileUIService.defaultAlbums,
        photosByAlbum: [UUID: [AlbumPhoto]] = FakeSocialProfileUIService.defaultAlbumPhotos
    ) {
        profileValue = profile
        self.friendsValue = friends
        self.pendingRequests = pendingRequests
        historyValue = history
        albumValues = albums
        self.photosByAlbum = photosByAlbum
    }

    func acceptedFriends() async throws -> [FriendRelation] {
        friendsValue.filter { $0.status == .accepted }
    }

    func pendingFriendRequests() async throws -> [FriendRequest] {
        pendingRequests
    }

    func requestFriend(uniqueID: String) async throws -> FriendRequest {
        let normalized = uniqueID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SocialUIError.invalidInput }
        let request = FriendRequest(
            id: UUID(),
            requesterID: UUID(),
            requesterName: normalized,
            requesterUniqueID: normalized,
            createdAt: Date()
        )
        return request
    }

    func respondFriendRequest(id: UUID, accepted: Bool) async throws {
        guard let requestIndex = pendingRequests.firstIndex(where: { $0.id == id }) else {
            throw SocialUIError.notFound
        }
        let request = pendingRequests.remove(at: requestIndex)
        guard accepted else { return }
        friendsValue.append(
            FriendRelation(
                id: UUID(),
                friendID: request.requesterID,
                friendName: request.requesterName,
                friendUniqueID: request.requesterUniqueID,
                status: .accepted
            )
        )
    }

    func removeFriend(id: UUID) async throws {
        guard let index = friendsValue.firstIndex(where: { $0.id == id }) else {
            throw SocialUIError.notFound
        }
        friendsValue.remove(at: index)
    }

    func currentProfile() async throws -> UserProfile? {
        profileValue
    }

    func updateProfile(displayName: String) async throws -> UserProfile {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 80,
              let profileValue else { throw SocialUIError.invalidInput }
        let updated = UserProfile(
            id: profileValue.id,
            userUniqueID: profileValue.userUniqueID,
            displayName: normalized,
            avatarPath: profileValue.avatarPath
        )
        self.profileValue = updated
        return updated
    }

    func stampCardStats() async throws -> StampCardStats? {
        stampStats
    }

    func pendingRakugakis() async throws -> [RakugakiHistoryItem] {
        historyValue.filter { $0.status.isPendingStatus }
    }

    func historyRakugakis() async throws -> [RakugakiHistoryItem] {
        historyValue.filter { $0.status.isApprovedStatus }
    }

    func approveRakugaki(id: UUID, approved: Bool) async throws -> RakugakiHistoryItem {
        guard let index = historyValue.firstIndex(where: { $0.id == id }) else {
            throw SocialUIError.notFound
        }
        let old = historyValue[index]
        guard old.canModerate, old.status.isPendingStatus else {
            throw SocialUIError.permissionDenied
        }
        let updated = RakugakiHistoryItem(
            id: old.id,
            photoID: old.photoID,
            photoTitle: old.photoTitle,
            authorName: old.authorName,
            assetPath: old.assetPath,
            status: approved ? .approved : .rejected,
            createdAt: old.createdAt,
            canModerate: old.canModerate
        )
        historyValue[index] = updated
        return updated
    }

    func albums() async throws -> [AlbumSummary] {
        albumValues
    }

    func createAlbum(title: String, description: String) async throws -> AlbumSummary {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, normalizedTitle.count <= 80 else {
            throw SocialUIError.invalidInput
        }
        let album = AlbumSummary(
            id: UUID(),
            title: normalizedTitle,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            photoCount: 0
        )
        albumValues.insert(album, at: 0)
        photosByAlbum[album.id] = []
        return album
    }

    func albumPhotos(albumID: UUID) async throws -> [AlbumPhoto] {
        guard albumValues.contains(where: { $0.id == albumID }) else {
            throw SocialUIError.notFound
        }
        return photosByAlbum[albumID] ?? []
    }

    func addPhoto(photoID: UUID, to albumID: UUID) async throws -> AlbumPhoto {
        guard let albumIndex = albumValues.firstIndex(where: { $0.id == albumID }) else {
            throw SocialUIError.notFound
        }
        let photo = AlbumPhoto(
            id: UUID(),
            photoID: photoID,
            title: "写真 \(photoID.uuidString.prefix(8))",
            addedAt: Date()
        )
        photosByAlbum[albumID, default: []].append(photo)
        let old = albumValues[albumIndex]
        albumValues[albumIndex] = AlbumSummary(
            id: old.id,
            title: old.title,
            description: old.description,
            createdAt: old.createdAt,
            photoCount: photosByAlbum[albumID]?.count ?? old.photoCount
        )
        return photo
    }

    func removePhoto(photoID: UUID, from albumID: UUID) async throws {
        guard albumValues.contains(where: { $0.id == albumID }) else {
            throw SocialUIError.notFound
        }
        photosByAlbum[albumID]?.removeAll { $0.photoID == photoID }
        guard let albumIndex = albumValues.firstIndex(where: { $0.id == albumID }) else { return }
        let old = albumValues[albumIndex]
        albumValues[albumIndex] = AlbumSummary(
            id: old.id,
            title: old.title,
            description: old.description,
            createdAt: old.createdAt,
            photoCount: photosByAlbum[albumID]?.count ?? 0
        )
    }

    func deleteAlbum(id: UUID) async throws {
        guard let index = albumValues.firstIndex(where: { $0.id == id }) else {
            throw SocialUIError.notFound
        }
        albumValues.remove(at: index)
        photosByAlbum.removeValue(forKey: id)
    }

    static let defaultProfile = UserProfile(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
        userUniqueID: "rakugaki-demo",
        displayName: "ラクガキユーザー"
    )

    static let defaultFriends: [FriendRelation] = [
        FriendRelation(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000111")!,
            friendID: UUID(uuidString: "00000000-0000-4000-8000-000000000112")!,
            friendName: "あおい",
            friendUniqueID: "aoi-map",
            status: .accepted
        )
    ]

    static let defaultRequests: [FriendRequest] = [
        FriendRequest(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000121")!,
            requesterID: UUID(uuidString: "00000000-0000-4000-8000-000000000122")!,
            requesterName: "みどり",
            requesterUniqueID: "midori-map",
            createdAt: Date(timeIntervalSince1970: 1_725_000_000)
        )
    ]

    static let defaultHistory: [RakugakiHistoryItem] = [
        RakugakiHistoryItem(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000131")!,
            photoID: UUID(uuidString: "00000000-0000-4000-8000-000000000132")!,
            photoTitle: "公園のラクガキ",
            authorName: "あおい",
            assetPath: "fixture/rakugaki-1.png",
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 1_725_000_000),
            canModerate: true
        )
    ]

    static let defaultAlbums: [AlbumSummary] = [
        AlbumSummary(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000141")!,
            title: "お気に入り",
            description: "あとで見返したい写真",
            createdAt: Date(timeIntervalSince1970: 1_724_000_000),
            photoCount: 1
        )
    ]

    static let defaultAlbumPhotos: [UUID: [AlbumPhoto]] = [
        UUID(uuidString: "00000000-0000-4000-8000-000000000141")!: [
            AlbumPhoto(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000151")!,
                photoID: UUID(uuidString: "00000000-0000-4000-8000-000000000132")!,
                title: "公園のラクガキ",
                addedAt: Date(timeIntervalSince1970: 1_724_000_000)
            )
        ]
    ]
}
