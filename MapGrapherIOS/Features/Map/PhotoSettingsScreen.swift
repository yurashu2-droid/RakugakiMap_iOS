import Foundation
import MapGrapherCore
import SwiftUI

enum PhotoDetailUIError: Error, Equatable, Sendable {
    case permissionDenied
    case notFound
    case offline
    case invalidInput
    case serviceUnavailable
}

struct PhotoSettingsSnapshot: Equatable, Sendable {
    let visibility: MapGrapherCore.Visibility
    let drawPermission: MapGrapherCore.Visibility
    let requiresApproval: Bool
}

struct PhotoLikeState: Equatable, Sendable {
    let isLiked: Bool
    let likeCount: Int
}

@MainActor
protocol PhotoDetailUIService {
    var dataMode: SocialUIDataMode { get }
    func toggleLike(photoID: UUID, liked: Bool) async throws -> PhotoLikeState
    func updatePhotoSettings(
        photoID: UUID,
        visibility: MapGrapherCore.Visibility,
        drawPermission: MapGrapherCore.Visibility,
        requiresApproval: Bool
    ) async throws -> PhotoSettingsSnapshot
    func deletePhoto(photoID: UUID) async throws
}

@MainActor
final class FakePhotoDetailUIService: PhotoDetailUIService {
    let dataMode: SocialUIDataMode = .fake
    private var likeStates: [UUID: PhotoLikeState] = [:]
    private var settings: [UUID: PhotoSettingsSnapshot] = [:]

    init(
        likeStates: [UUID: PhotoLikeState] = [:],
        settings: [UUID: PhotoSettingsSnapshot] = [:]
    ) {
        self.likeStates = likeStates
        self.settings = settings
    }

    func toggleLike(photoID: UUID, liked: Bool) async throws -> PhotoLikeState {
        let current = likeStates[photoID] ?? PhotoLikeState(isLiked: false, likeCount: 0)
        let nextCount = max(0, current.likeCount + (liked == current.isLiked ? 0 : (liked ? 1 : -1)))
        let updated = PhotoLikeState(isLiked: liked, likeCount: nextCount)
        likeStates[photoID] = updated
        return updated
    }

    func updatePhotoSettings(
        photoID: UUID,
        visibility: MapGrapherCore.Visibility,
        drawPermission: MapGrapherCore.Visibility,
        requiresApproval: Bool
    ) async throws -> PhotoSettingsSnapshot {
        let snapshot = PhotoSettingsSnapshot(
            visibility: visibility,
            drawPermission: drawPermission,
            requiresApproval: requiresApproval
        )
        settings[photoID] = snapshot
        return snapshot
    }

    func deletePhoto(photoID: UUID) async throws {
        likeStates.removeValue(forKey: photoID)
        settings.removeValue(forKey: photoID)
    }
}

@MainActor
final class PhotoSettingsScreenModel: ObservableObject {
    @Published private(set) var settings: PhotoSettingsSnapshot
    @Published private(set) var isSaving = false
    @Published private(set) var didSave = false
    @Published private(set) var error: Error?

    private let photoID: UUID
    private let service: any PhotoDetailUIService

    init(
        photoID: UUID,
        initial: PhotoSettingsSnapshot,
        service: any PhotoDetailUIService
    ) {
        self.photoID = photoID
        settings = initial
        self.service = service
    }

    func save(
        visibility: MapGrapherCore.Visibility,
        drawPermission: MapGrapherCore.Visibility,
        requiresApproval: Bool
    ) async {
        guard !isSaving else { return }
        isSaving = true
        didSave = false
        error = nil
        defer { isSaving = false }
        do {
            settings = try await service.updatePhotoSettings(
                photoID: photoID,
                visibility: visibility,
                drawPermission: drawPermission,
                requiresApproval: requiresApproval
            )
            didSave = true
        } catch {
            self.error = error
        }
    }
}

@MainActor
struct PhotoSettingsScreen: View {
    private let service: any PhotoDetailUIService
    @StateObject private var model: PhotoSettingsScreenModel
    @State private var visibility: MapGrapherCore.Visibility
    @State private var drawPermission: MapGrapherCore.Visibility
    @State private var requiresApproval: Bool

    init(
        photoID: UUID,
        initial: PhotoSettingsSnapshot,
        service: any PhotoDetailUIService = FakePhotoDetailUIService()
    ) {
        self.service = service
        _model = StateObject(
            wrappedValue: PhotoSettingsScreenModel(
                photoID: photoID,
                initial: initial,
                service: service
            )
        )
        _visibility = State(initialValue: initial.visibility)
        _drawPermission = State(initialValue: initial.drawPermission)
        _requiresApproval = State(initialValue: initial.requiresApproval)
    }

    var body: some View {
        Form {
            Section {
                if service.dataMode == .fake {
                    PrototypeNotice(message: AppStrings.socialFakeNotice)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("social.notice.fake")
                }
            }

            Section {
                Picker("posting.publish.visibility", selection: Binding(
                    get: { visibility.rawValue },
                    set: { rawValue in
                        if let value = MapGrapherCore.Visibility(rawValue: rawValue) {
                            visibility = value
                        }
                    }
                )) {
                    ForEach(PhotoSettingsScreen.visibilityChoices, id: \.rawValue) { value in
                        Text(value.photoVisibilityLabel).tag(value.rawValue)
                    }
                }
                .accessibilityIdentifier("photo.settings.visibility")

                Picker("posting.publish.draw-permission", selection: Binding(
                    get: { drawPermission.rawValue },
                    set: { rawValue in
                        if let value = MapGrapherCore.Visibility(rawValue: rawValue) {
                            drawPermission = value
                        }
                    }
                )) {
                    ForEach(PhotoSettingsScreen.visibilityChoices, id: \.rawValue) { value in
                        Text(value.photoDrawPermissionLabel).tag(value.rawValue)
                    }
                }
                .accessibilityIdentifier("photo.settings.draw-permission")

                Toggle("posting.publish.approval", isOn: $requiresApproval)
                    .accessibilityIdentifier("photo.settings.approval")
            } header: {
                Text("photo.settings.access.header")
            } footer: {
                Text("photo.settings.access.detail")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button {
                    Task {
                        await model.save(
                            visibility: visibility,
                            drawPermission: drawPermission,
                            requiresApproval: requiresApproval
                        )
                    }
                } label: {
                    if model.isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        Label("profile.save", systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSaving)
                .accessibilityIdentifier("photo.settings.save")
            }

            if model.didSave {
                if service.dataMode == .fake {
                    Text(AppStrings.socialFakeNotice)
                        .font(.subheadline)
                        .accessibilityIdentifier("social.notice.fake")
                } else {
                    Text("photo.settings.saved")
                        .font(.subheadline)
                        .accessibilityIdentifier("photo.settings.saved")
                }
            }
            if let error = model.error {
                Text(PhotoDetailUIMessage.errorKey(for: error))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.settings.error")
            }
        }
        .navigationTitle("photo.settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.photo-settings")
    }

    private static let visibilityChoices: [MapGrapherCore.Visibility] = [
        .onlyMe,
        .friends,
        .anyone
    ]
}

enum PhotoDetailUIMessage {
    static func errorKey(for error: Error) -> LocalizedStringKey {
        guard let error = error as? PhotoDetailUIError else {
            return "social.error"
        }
        switch error {
        case .permissionDenied:
            return "social.error.permission"
        case .notFound:
            return "social.error.not-found"
        case .offline:
            return "social.error.offline"
        case .invalidInput, .serviceUnavailable:
            return "social.error"
        }
    }
}

private extension MapGrapherCore.Visibility {
    var photoVisibilityLabel: LocalizedStringKey {
        switch self {
        case .onlyMe:
            "posting.visibility.only-me"
        case .friends:
            "posting.visibility.friends"
        case .anyone:
            "posting.visibility.anyone"
        }
    }

    var photoDrawPermissionLabel: LocalizedStringKey {
        switch self {
        case .onlyMe:
            "posting.draw-permission.only-me"
        case .friends:
            "posting.draw-permission.friends"
        case .anyone:
            "posting.draw-permission.anyone"
        }
    }
}
