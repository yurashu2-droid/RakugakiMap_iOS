import Combine

@MainActor
final class ProfileScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var profile: UserProfile?
    @Published private(set) var stampStats: StampCardStats?
    @Published private(set) var error: Error?

    private let service: any SocialProfileUIService

    init(service: any SocialProfileUIService) {
        self.service = service
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        error = nil

        do {
            profile = try await service.currentProfile()
            stampStats = try? await service.stampCardStats()
            state = profile == nil ? .empty : .content
        } catch {
            profile = nil
            stampStats = nil
            self.error = error
            state = .error
        }
    }
}

@MainActor
final class ProfileEditScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var profile: UserProfile?
    @Published private(set) var error: Error?
    @Published private(set) var isSaving = false
    @Published private(set) var didSave = false

    private let service: any SocialProfileUIService

    init(service: any SocialProfileUIService) {
        self.service = service
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            profile = try await service.currentProfile()
            state = profile == nil ? .empty : .content
        } catch {
            self.error = error
            state = .error
        }
    }

    func save(displayName: String) async {
        guard !isSaving else { return }
        isSaving = true
        didSave = false
        error = nil
        defer { isSaving = false }

        do {
            profile = try await service.updateProfile(displayName: displayName)
            didSave = true
            state = .content
        } catch {
            self.error = error
        }
    }
}
