import Foundation
import SwiftUI
import UIKit
import MapGrapherCore

enum PhotoPermissionState: Equatable {
    case loading
    case loaded(PhotoPermissions)
    case forbidden
    case notFound
    case offline
    case error
}

private enum RakugakiLoadState: Equatable {
    case loading
    case loaded
    case failed
}

@MainActor
struct PhotoDetailScreen: View {
    let photo: Photo
    let photoReader: any PhotoReading
    let rakugakiReader: any PhotoRakugakiReading
    let assetLoader: PrivateAssetLoader?
    let sessionContext: SessionContext?
    let onOpenAR: () -> Void
    let photoService: any PhotoDetailUIService
    let existingPhotoRakugakiService: (any ExistingPhotoRakugakiServing)?

    @Environment(\.dismiss) private var dismiss
    @State private var permissionState: PhotoPermissionState = .loading
    @State private var photoImage: UIImage?
    @State private var compositeImage: UIImage?
    @State private var rakugakis: [PhotoRakugaki] = []
    @State private var rakugakiLoadState: RakugakiLoadState = .loading
    @State private var rakugakiLoadGeneration = 0
    @State private var likeState: PhotoLikeState
    @State private var isPhotoOperationBusy = false
    @State private var photoOperationError: Error?
    @State private var didCompletePhotoAction = false
    @State private var showsDeleteDialog = false
    @State private var showsRakugakiFlow = false

    init(
        photo: Photo,
        photoReader: any PhotoReading,
        rakugakiReader: any PhotoRakugakiReading = FakePhotoRakugakiReader(),
        assetLoader: PrivateAssetLoader? = nil,
        sessionContext: SessionContext? = nil,
        existingPhotoRakugakiService: (any ExistingPhotoRakugakiServing)? = nil,
        onOpenAR: @escaping () -> Void = {},
        photoService: any PhotoDetailUIService = FakePhotoDetailUIService()
    ) {
        self.photo = photo
        self.photoReader = photoReader
        self.rakugakiReader = rakugakiReader
        self.assetLoader = assetLoader
        self.sessionContext = sessionContext
        self.existingPhotoRakugakiService = existingPhotoRakugakiService
        self.onOpenAR = onOpenAR
        self.photoService = photoService
        _likeState = State(
            initialValue: PhotoLikeState(isLiked: photo.likedByMe, likeCount: photo.likeCount)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    if canView {
                        PhotoHeroView(photo: photo, image: compositeImage ?? photoImage)

                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(photo.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppColors.ink)
                            Text("map.photo-detail.author")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.ink.opacity(0.70))
                            Text(photo.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(AppColors.ink.opacity(0.62))
                        }
                    }

                    permissionSection
                    if canView { rakugakiSection }
                }
                .padding(.horizontal, AppSpacing.xLarge)
                .padding(.vertical, AppSpacing.large)
            }
            .refreshable { await loadPermissions() }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(Text("map.photo-detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("route.close") {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .confirmationDialog(
            "photo.delete.confirm",
            isPresented: $showsDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("photo.delete", role: .destructive) {
                Task { await deletePhoto() }
            }
            Button("posting.close.cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showsRakugakiFlow) {
            if let existingPhotoRakugakiService {
                AddRakugakiFlow(photo: photo, service: existingPhotoRakugakiService)
            }
        }
        .onChange(of: showsRakugakiFlow) { _, isPresented in
            if !isPresented { Task { await reloadRakugakis() } }
        }
        .accessibilityIdentifier("screen.photo-detail")
        .accessibilityLabel(Text("map.photo-detail.title"))
        .task(id: photo.id) {
            await loadPermissions()
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("map.photo-detail.actions")
                .font(.headline)
                .foregroundStyle(AppColors.ink)

            HStack(spacing: AppSpacing.medium) {
                Button {
                    showsRakugakiFlow = true
                } label: {
                    Label("photo.draw", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canDraw || existingPhotoRakugakiService == nil)
                .accessibilityIdentifier("photo.draw.button")

                Button {
                    onOpenAR()
                } label: {
                    Label("photo.ar", systemImage: "arkit")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!canView)
                .accessibilityIdentifier("photo.ar.button")
            }

            HStack(spacing: AppSpacing.medium) {
                Button {
                    Task { await toggleLike() }
                } label: {
                    Label(
                        likeState.isLiked ? "photo.like.remove" : "photo.like",
                        systemImage: likeState.isLiked ? "heart.fill" : "heart"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!canView || isPhotoOperationBusy)
                .accessibilityIdentifier("photo.like.button")

                Text("\(likeState.likeCount)")
                    .font(.subheadline.monospacedDigit())
                    .accessibilityLabel(Text("photo.like.count"))
                    .accessibilityIdentifier("photo.like.count")
            }

            if isOwner {
                HStack(spacing: AppSpacing.medium) {
                    NavigationLink {
                        PhotoSettingsScreen(
                            photoID: photo.id,
                            initial: PhotoSettingsSnapshot(
                                visibility: photo.visibility,
                                drawPermission: photo.drawPermission,
                                requiresApproval: photo.requiresApproval
                            ),
                            service: photoService
                        )
                    } label: {
                        Label("photo.settings", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("photo.settings.button")

                    Button {
                        showsDeleteDialog = true
                    } label: {
                        Label("photo.delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isPhotoOperationBusy)
                    .accessibilityLabel(Text("photo.delete"))
                    .accessibilityIdentifier("photo.delete.button")
                }
            }

            if didCompletePhotoAction {
                SocialActionNotice(dataMode: photoService.dataMode)
            }
            if let photoOperationError {
                Text(PhotoDetailUIMessage.errorKey(for: photoOperationError))
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.action.error")
            }

            switch permissionState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel(Text("state.loading"))
                    .accessibilityIdentifier("photo.permissions.loading")
            case .loaded(let permissions) where !permissions.canView:
                Text("map.photo-detail.permission-denied")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.permissions.denied")
            case .loaded:
                EmptyView()
            case .forbidden:
                Text("map.photo-detail.permission-denied")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.permissions.denied")
            case .notFound:
                Text("map.photo-detail.not-found")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
            case .offline:
                Text("map.photo-detail.offline")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
            case .error:
                Text("state.error.default")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.large)
        .background(AppColors.mint.opacity(0.20), in: RoundedRectangle(cornerRadius: 18))
    }

    private var rakugakiSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("map.rakugaki-list.title")
                .font(.headline)
                .foregroundStyle(AppColors.ink)

            if rakugakiLoadState == .loading {
                ProgressView()
                    .accessibilityLabel(Text("state.loading"))
            } else if rakugakiLoadState == .failed {
                Text("state.error.default")
                    .foregroundStyle(AppColors.coral)
                Button("map.refresh") { Task { await reloadRakugakis() } }
                    .frame(minHeight: 44)
            } else if rakugakis.isEmpty {
                Text("map.rakugaki-list.empty")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(AppSpacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("map.rakugaki-list.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(rakugakis) { rakugaki in
                        HStack(spacing: AppSpacing.medium) {
                            Image(systemName: "scribble.variable")
                                .foregroundStyle(AppColors.coral)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                                Text(rakugaki.authorName)
                                    .font(.subheadline.weight(.semibold))
                                Text("map.rakugaki.status.approved")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.ink.opacity(0.70))
                            }
                            Spacer()
                            Text(rakugaki.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(AppColors.ink.opacity(0.62))
                        }
                        .padding(.vertical, AppSpacing.small)
                    }
                }
                .accessibilityIdentifier("map.rakugaki-list")
            }
        }
    }

    private var canView: Bool {
        if case .loaded(let permissions) = permissionState {
            return permissions.canView
        }
        return false
    }

    private var canDraw: Bool {
        if case .loaded(let permissions) = permissionState {
            return permissions.canDraw
        }
        return false
    }

    private var isOwner: Bool {
        if case .loaded(let permissions) = permissionState {
            return permissions.isOwner
        }
        return false
    }

    private func toggleLike() async {
        guard canView, !isPhotoOperationBusy else { return }
        isPhotoOperationBusy = true
        photoOperationError = nil
        didCompletePhotoAction = false
        defer { isPhotoOperationBusy = false }
        do {
            likeState = try await photoService.toggleLike(
                photoID: photo.id,
                liked: !likeState.isLiked
            )
            didCompletePhotoAction = true
        } catch {
            photoOperationError = error
        }
    }

    private func deletePhoto() async {
        guard isOwner, !isPhotoOperationBusy else { return }
        isPhotoOperationBusy = true
        photoOperationError = nil
        didCompletePhotoAction = false
        defer { isPhotoOperationBusy = false }
        do {
            try await photoService.deletePhoto(photoID: photo.id)
            if photoService.dataMode == .live {
                dismiss()
            } else {
                didCompletePhotoAction = true
            }
        } catch {
            photoOperationError = error
        }
    }

    private func loadPermissions() async {
        permissionState = .loading
        photoImage = nil
        compositeImage = nil
        rakugakis = []
        rakugakiLoadState = .loading
        rakugakiLoadGeneration &+= 1
        do {
            let permissions = try await photoReader.permissions(photoID: photo.id)
            guard !Task.isCancelled else { return }
            permissionState = .loaded(permissions)
            guard permissions.canView else { return }
            if let assetLoader, let sessionContext {
                let image = try await assetLoader.load(
                    asset: photo.asset,
                    targetPixelSize: CGSize(width: 1200, height: 1200),
                    context: sessionContext
                )
                guard !Task.isCancelled else { return }
                photoImage = image
            }
            await reloadRakugakis()
        } catch let error as PhotoReadingError {
            guard !Task.isCancelled else { return }
            switch error {
            case .permissionDenied, .forbidden:
                permissionState = .forbidden
            case .notFound:
                permissionState = .notFound
            case .offline:
                permissionState = .offline
            case .serviceUnavailable, .unknown:
                permissionState = .error
            }
        } catch let error as AppFailure {
            guard !Task.isCancelled else { return }
            photoImage = nil
            switch error {
            case .forbidden, .needsLogin, .cancelled:
                permissionState = .forbidden
            case .notFound:
                permissionState = .notFound
            case .offline:
                permissionState = .offline
            default:
                permissionState = .error
            }
        } catch {
            guard !Task.isCancelled else { return }
            photoImage = nil
            permissionState = .error
        }
    }

    private func reloadRakugakis() async {
        guard canView else { return }
        rakugakiLoadGeneration &+= 1
        let generation = rakugakiLoadGeneration
        rakugakiLoadState = .loading
        do {
            let fetched = try await rakugakiReader.approved(photoID: photo.id)
            let rows = fetched.sorted { $0.createdAt < $1.createdAt }
            guard !Task.isCancelled, generation == rakugakiLoadGeneration else { return }
            var overlays: [UIImage] = []
            if let assetLoader, let sessionContext, let photoImage {
                for row in rows {
                    let image = try await assetLoader.load(
                        asset: row.asset,
                        targetPixelSize: CGSize(width: 1200, height: 1200),
                        context: sessionContext
                    )
                    guard !Task.isCancelled, generation == rakugakiLoadGeneration else { return }
                    overlays.append(image)
                }
                compositeImage = PhotoCompositeRenderer.render(photo: photoImage,
                                                                overlays: overlays)
            }
            rakugakis = rows
            rakugakiLoadState = .loaded
        } catch {
            guard !Task.isCancelled, generation == rakugakiLoadGeneration else { return }
            rakugakiLoadState = .failed
        }
    }
}

@MainActor
private struct PhotoHeroView: View {
    let photo: Photo
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                VStack(spacing: AppSpacing.small) {
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(AppColors.coral)
                        .accessibilityHidden(true)
                    Text("map.photo-detail.asset-pending")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.ink.opacity(0.72))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
            }
        }
        .background(AppColors.mint.opacity(0.30), in: RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(photo.title))
        .accessibilityIdentifier("photo.asset")
    }
}
