import Combine

@MainActor
final class AlbumListScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var albums: [AlbumSummary] = []
    @Published private(set) var error: Error?
    @Published private(set) var isWorking = false
    @Published private(set) var didCompleteAction = false

    private let service: any SocialProfileUIService

    init(service: any SocialProfileUIService) {
        self.service = service
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            albums = try await service.albums()
            state = albums.isEmpty ? .empty : .content
        } catch {
            albums = []
            self.error = error
            state = .error
        }
    }

    func createAlbum(title: String, description: String) async -> AlbumSummary? {
        guard !isWorking else { return nil }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            let album = try await service.createAlbum(title: title, description: description)
            didCompleteAction = true
            await load()
            return album
        } catch {
            self.error = error
            return nil
        }
    }

    func markCreated() {
        didCompleteAction = true
    }

    func delete(album: AlbumSummary) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            try await service.deleteAlbum(id: album.id)
            albums.removeAll { $0.id == album.id }
            didCompleteAction = true
            state = albums.isEmpty ? .empty : .content
        } catch {
            self.error = error
        }
    }
}

@MainActor
final class AlbumCreateScreenModel: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var error: Error?
    @Published private(set) var didCompleteAction = false

    private let service: any SocialProfileUIService

    init(service: any SocialProfileUIService) {
        self.service = service
    }

    func create(title: String, description: String) async -> AlbumSummary? {
        guard !isWorking else { return nil }
        isWorking = true
        error = nil
        didCompleteAction = false
        defer { isWorking = false }
        do {
            let album = try await service.createAlbum(title: title, description: description)
            didCompleteAction = true
            return album
        } catch {
            self.error = error
            return nil
        }
    }
}

@MainActor
final class AlbumDetailScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var photos: [AlbumPhoto] = []
    @Published private(set) var error: Error?
    @Published private(set) var isWorking = false
    @Published private(set) var didCompleteAction = false

    private let albumID: UUID
    private let service: any SocialProfileUIService

    init(albumID: UUID, service: any SocialProfileUIService) {
        self.albumID = albumID
        self.service = service
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            photos = try await service.albumPhotos(albumID: albumID)
            state = photos.isEmpty ? .empty : .content
        } catch {
            photos = []
            self.error = error
            state = .error
        }
    }

    func addPhoto(photoID: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            _ = try await service.addPhoto(photoID: photoID, to: albumID)
            didCompleteAction = true
            await load()
        } catch {
            self.error = error
        }
    }

    func removePhoto(_ photo: AlbumPhoto) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            try await service.removePhoto(photoID: photo.photoID, from: albumID)
            photos.removeAll { $0.id == photo.id }
            didCompleteAction = true
            state = photos.isEmpty ? .empty : .content
        } catch {
            self.error = error
        }
    }

    func deleteAlbum() async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            try await service.deleteAlbum(id: albumID)
            didCompleteAction = true
        } catch {
            self.error = error
        }
    }
}
