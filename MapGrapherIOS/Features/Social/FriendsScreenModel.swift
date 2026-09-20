import Combine
import Foundation

@MainActor
final class FriendsScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var friends: [FriendRelation] = []
    @Published private(set) var requests: [FriendRequest] = []
    @Published private(set) var error: Error?
    @Published private(set) var isWorking = false
    @Published private(set) var didCompleteAction = false

    private let service: any SocialProfileUIService

    init(service: any SocialProfileUIService) {
        self.service = service
    }

    func loadFriends() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            friends = try await service.acceptedFriends()
            state = friends.isEmpty ? .empty : .content
        } catch {
            friends = []
            self.error = error
            state = .error
        }
    }

    func loadRequests() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            requests = try await service.pendingFriendRequests()
            state = requests.isEmpty ? .empty : .content
        } catch {
            requests = []
            self.error = error
            state = .error
        }
    }

    func requestFriend(uniqueID: String) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            _ = try await service.requestFriend(uniqueID: uniqueID)
            didCompleteAction = true
        } catch {
            self.error = error
        }
    }

    func respond(to request: FriendRequest, accepted: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            try await service.respondFriendRequest(id: request.id, accepted: accepted)
            requests.removeAll { $0.id == request.id }
            didCompleteAction = true
            state = requests.isEmpty ? .empty : .content
        } catch {
            self.error = error
        }
    }

    func remove(friend: FriendRelation) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            try await service.removeFriend(id: friend.id)
            friends.removeAll { $0.id == friend.id }
            didCompleteAction = true
            state = friends.isEmpty ? .empty : .content
        } catch {
            self.error = error
        }
    }
}
