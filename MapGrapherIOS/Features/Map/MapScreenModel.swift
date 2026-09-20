import Combine
import Foundation
import MapGrapherCore

@MainActor
protocol PhotoReading {
    func nearby(center: GeoPoint, radiusM: Double) async throws -> [Photo]
    func permissions(photoID: UUID) async throws -> PhotoPermissions
}

enum PhotoReadingError: Error, Equatable, Sendable {
    case offline
    case permissionDenied
    case forbidden
    case notFound
    case serviceUnavailable
    case unknown
}

enum MapLocationState: Equatable, Sendable {
    case notDetermined
    case permissionDenied
    case unavailable
    case invalid
    case approximate(GeoPoint)
    case ready(GeoPoint)
}

@MainActor
protocol MapLocationProviding {
    func requestCurrentLocation() async -> MapLocationState
}

enum MapScreenState: Equatable {
    case idle
    case locating
    case loading
    case content
    case empty
    case locationUnavailable
    case permissionDenied
    case offline
    case error
}

enum PhotoFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case friends
    case recent24Hours

    var id: String { rawValue }
}

@MainActor
final class MapScreenModel: ObservableObject {
    @Published private(set) var state: MapScreenState = .idle
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var currentLocation: GeoPoint?
    @Published private(set) var selectedFilter: PhotoFilter = .all

    private let photoReader: any PhotoReading
    private let locationProvider: any MapLocationProviding
    private let now: () -> Date
    private var requestGeneration = 0
    private(set) var lastSearchCenter: GeoPoint?

    init(
        photoReader: any PhotoReading,
        locationProvider: any MapLocationProviding = FakeMapLocationProvider(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.photoReader = photoReader
        self.locationProvider = locationProvider
        self.now = now
    }

    var visiblePhotos: [Photo] {
        switch selectedFilter {
        case .all:
            return photos
        case .friends:
            // 閲覧権限はサーバーを正とし、この絞り込みは公開範囲だけを対象にする。
            return photos.filter { $0.visibility == .friends }
        case .recent24Hours:
            let cutoff = now().addingTimeInterval(-24 * 60 * 60)
            return photos.filter { $0.createdAt >= cutoff && $0.createdAt <= now() }
        }
    }

    func selectFilter(_ filter: PhotoFilter) {
        selectedFilter = filter
    }

    func start() async {
        requestGeneration &+= 1
        let generation = requestGeneration
        photos = []
        state = .locating

        let locationState = await locationProvider.requestCurrentLocation()
        guard generation == requestGeneration else { return }

        switch locationState {
        case .ready(let point), .approximate(let point):
            currentLocation = point
            await search(center: point)
        case .permissionDenied:
            state = .permissionDenied
        case .notDetermined, .unavailable, .invalid:
            state = .locationUnavailable
        }
    }

    func refresh() async {
        if let currentLocation {
            await search(center: currentLocation)
        } else {
            await start()
        }
    }

    func search(center: GeoPoint, radiusM: Double = 500) async {
        guard radiusM.isFinite, radiusM > 0 else {
            state = .error
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        lastSearchCenter = center
        photos = []
        state = .loading

        do {
            let result = try await photoReader.nearby(center: center, radiusM: radiusM)
            guard generation == requestGeneration else { return }
            photos = result
            state = result.isEmpty ? .empty : .content
        } catch let error as PhotoReadingError {
            guard generation == requestGeneration else { return }
            state = state(for: error)
        } catch {
            guard generation == requestGeneration else { return }
            state = .error
        }
    }

    func cancelPendingSearch() {
        requestGeneration &+= 1
    }

    private func state(for error: PhotoReadingError) -> MapScreenState {
        switch error {
        case .offline:
            .offline
        case .permissionDenied, .forbidden:
            .permissionDenied
        case .notFound, .serviceUnavailable, .unknown:
            .error
        }
    }
}

@MainActor
final class FakeMapLocationProvider: MapLocationProviding {
    var state: MapLocationState

    init(state: MapLocationState = .ready(GeoPoint(latitude: 35.0, longitude: 139.0)!)) {
        self.state = state
    }

    func requestCurrentLocation() async -> MapLocationState {
        state
    }
}

@MainActor
final class FakePhotoReading: PhotoReading {
    var nearbyResult: Result<[Photo], PhotoReadingError>
    var permissionResults: [UUID: Result<PhotoPermissions, PhotoReadingError>]

    init(
        nearbyResult: Result<[Photo], PhotoReadingError> = .success(FakePhotoReading.samplePhotos),
        permissionResults: [UUID: Result<PhotoPermissions, PhotoReadingError>] = [:]
    ) {
        self.nearbyResult = nearbyResult
        self.permissionResults = permissionResults
    }

    func nearby(center: GeoPoint, radiusM: Double) async throws -> [Photo] {
        try nearbyResult.get()
    }

    func permissions(photoID: UUID) async throws -> PhotoPermissions {
        if let result = permissionResults[photoID] {
            return try result.get()
        }
        return PhotoPermissions(canView: true, canDraw: true, isOwner: false)
    }

    static let samplePhotos: [Photo] = [
        Photo(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            ownerID: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!,
            title: "公園のラクガキ",
            location: GeoPoint(latitude: 35.0001, longitude: 139.0001)!,
            visibility: .anyone,
            drawPermission: .friends,
            requiresApproval: false,
            createdAt: Date(),
            asset: AssetReference(bucket: "photos", path: "fixture/photo-1.jpg")!,
            thumbnail: AssetReference(bucket: "photos", path: "fixture/photo-1-thumb.jpg"),
            likeCount: 3,
            likedByMe: false
        )!
    ]
}
