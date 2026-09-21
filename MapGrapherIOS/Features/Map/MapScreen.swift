import SwiftUI
import MapGrapherCore

@MainActor
struct MapScreen: View {
    let isUITesting: Bool
    let onPresentRoute: (AppRoute) -> Void
    private let photoReader: any PhotoReading
    private let photoRakugakiReader: any PhotoRakugakiReading
    private let assetLoader: PrivateAssetLoader?
    private let sessionContext: SessionContext?
    private let photoService: any PhotoDetailUIService
    private let existingPhotoRakugakiService: (any ExistingPhotoRakugakiServing)?

    @StateObject private var model: MapScreenModel
    @State private var sheetRoute: MapSheetRoute?
    @State private var selectedPhoto: Photo?
    @State private var pendingARPhotoID: UUID?
    @State private var trackingRequest = 0
    @State private var isFollowingHeading = false
    @State private var usesAerialImagery = false

    init(
        isUITesting: Bool = false,
        photoReader: any PhotoReading = FakePhotoReading(),
        photoRakugakiReader: any PhotoRakugakiReading = FakePhotoRakugakiReader(),
        locationProvider: any MapLocationProviding = FakeMapLocationProvider(),
        assetLoader: PrivateAssetLoader? = nil,
        sessionContext: SessionContext? = nil,
        existingPhotoRakugakiService: (any ExistingPhotoRakugakiServing)? = nil,
        photoService: any PhotoDetailUIService = FakePhotoDetailUIService(),
        onPresentRoute: @escaping (AppRoute) -> Void = { _ in }
    ) {
        self.isUITesting = isUITesting
        self.onPresentRoute = onPresentRoute
        self.photoReader = photoReader
        self.photoRakugakiReader = photoRakugakiReader
        self.assetLoader = assetLoader
        self.sessionContext = sessionContext
        self.existingPhotoRakugakiService = existingPhotoRakugakiService
        self.photoService = photoService
        _model = StateObject(
            wrappedValue: MapScreenModel(
                photoReader: photoReader,
                locationProvider: locationProvider
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                MapCanvasView(
                    photos: model.visiblePhotos,
                    center: model.currentLocation,
                    assetLoader: assetLoader,
                    sessionContext: sessionContext,
                    showsUserLocation: !isUITesting,
                    usesAerialImagery: usesAerialImagery,
                    trackingRequest: trackingRequest,
                    onSelect: presentDetail(for:),
                    onRegionSettled: search(center:),
                    onTrackingChanged: { isFollowingHeading = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: AppSpacing.medium) {
                    filterBar
                    stateOverlay
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.top, AppSpacing.small)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            usesAerialImagery.toggle()
                        } label: {
                            Image(systemName: usesAerialImagery ? "map.fill" : "globe.americas.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(usesAerialImagery ? AppColors.paper : AppColors.ink)
                                .frame(width: 52, height: 52)
                                .background(usesAerialImagery ? AppColors.coral : AppColors.paper,
                                            in: Circle())
                                .overlay {
                                    Circle().stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                                }
                        }
                        .accessibilityLabel(usesAerialImagery ? "標準地図に切り替え" : "航空写真に切り替え")
                        .accessibilityIdentifier("map.imagery.toggle")
                        .padding(.trailing, AppSpacing.small)
                        Button {
                            trackingRequest &+= 1
                        } label: {
                            Image(systemName: "location.north.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(isFollowingHeading ? AppColors.paper : AppColors.ink)
                                .frame(width: 52, height: 52)
                                .background(isFollowingHeading ? AppColors.coral : AppColors.paper,
                                            in: Circle())
                                .overlay {
                                    Circle().stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                                }
                        }
                        .disabled(model.currentLocation == nil || isUITesting)
                        .accessibilityLabel(Text("map.current-location.button"))
                        .accessibilityIdentifier("map.current-location.button")
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.bottom, AppSpacing.medium)
            }
            .background(AppColors.paper)
            .navigationTitle(AppStrings.map)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onPresentRoute(.arPreview)
                    } label: {
                        Label(AppStrings.arPreviewButton, systemImage: "arkit")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("map.ar-preview.button")
                    .accessibilityLabel(Text(AppStrings.arPreviewButton))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheetRoute = .list
                    } label: {
                        Label("map.photo-list.open", systemImage: "list.bullet")
                            .labelStyle(.iconOnly)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(Text("map.photo-list.open"))
                    .accessibilityIdentifier("map.photo-list.button")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        onPresentRoute(.postComposer)
                    } label: {
                        Label("投稿", systemImage: "camera.fill")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("map.post.button")

                    Button {
                        onPresentRoute(.spatialARDrawing)
                    } label: {
                        Label("空間に描く", systemImage: "scribble.variable")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("map.spatial-ar-drawing.button")
                    .accessibilityLabel("空間に描く")
                }
            }
            .task {
                await model.start()
            }
            .onDisappear {
                model.cancelPendingSearch()
            }
            .sheet(item: $sheetRoute, onDismiss: {
                if let photoID = pendingARPhotoID {
                    pendingARPhotoID = nil
                    onPresentRoute(.arPhoto(photoID))
                }
            }) { route in
                sheetView(for: route)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.map")
        .accessibilityLabel(Text(AppStrings.map))
    }

    private var filterBar: some View {
        HStack(spacing: AppSpacing.small) {
            ForEach(PhotoFilter.allCases) { filter in
                Button(filter.titleKey) {
                    model.selectFilter(filter)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    model.selectedFilter == filter ? AppColors.paper : AppColors.ink
                )
                .padding(.horizontal, AppSpacing.medium)
                .frame(minHeight: 44)
                .background(
                    model.selectedFilter == filter ? AppColors.coral : AppColors.paper,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                }
                .accessibilityIdentifier("map.filter.\(filter.rawValue == "recent24Hours" ? "recent" : filter.rawValue)")
                .accessibilityAddTraits(model.selectedFilter == filter ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.filters")
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch model.state {
        case .idle, .locating:
            MapStatusCard(
                title: "map.location.loading",
                detail: "map.location.loading.detail",
                showsProgress: true
            )
        case .loading:
            MapStatusCard(
                title: "map.loading",
                detail: "map.loading.detail",
                showsProgress: true
            )
        case .content:
            if model.visiblePhotos.isEmpty {
                MapStatusCard(
                    title: "map.filter.empty.title",
                    detail: "map.filter.empty.detail"
                )
            } else {
                MapStatusCard(title: "map.content.title", detail: "map.content.detail")
            }
        case .empty:
            MapStatusCard(
                title: "map.empty.title",
                detail: "map.empty.detail",
                actionTitle: "map.refresh",
                action: refresh
            )
        case .locationUnavailable:
            MapStatusCard(
                title: "map.location.unavailable.title",
                detail: "map.location.unavailable.detail",
                actionTitle: "map.location.retry",
                action: refresh
            )
        case .permissionDenied:
            MapStatusCard(
                title: "map.location.permission.title",
                detail: "map.location.permission.detail",
                actionTitle: "map.location.retry",
                action: refresh
            )
        case .offline:
            MapStatusCard(
                title: "map.offline.title",
                detail: "map.offline.detail",
                actionTitle: "map.refresh",
                action: refresh
            )
        case .error:
            MapStatusCard(
                title: "map.error.title",
                detail: "map.error.detail",
                actionTitle: "map.refresh",
                action: refresh
            )
        }
    }

    @ViewBuilder
    private func sheetView(for route: MapSheetRoute) -> some View {
        switch route {
        case .list:
            PhotoListScreen(
                photos: model.visiblePhotos,
                filter: model.selectedFilter,
                detail: { photo in detail(for: photo) }
            )
        case .detail:
            if let selectedPhoto {
                detail(for: selectedPhoto)
            } else {
                ContentUnavailableView("map.photo-detail.not-found", systemImage: "photo")
            }
        }
    }

    private func detail(for photo: Photo) -> some View {
        PhotoDetailScreen(
            photo: photo,
            photoReader: photoReader,
            rakugakiReader: photoRakugakiReader,
            assetLoader: assetLoader,
            sessionContext: sessionContext,
            existingPhotoRakugakiService: existingPhotoRakugakiService,
            onOpenAR: {
                pendingARPhotoID = photo.id
                sheetRoute = nil
            },
            photoService: photoService
        )
    }

    private func presentDetail(for photo: Photo) {
        selectedPhoto = photo
        sheetRoute = .detail
    }

    private func search(center: GeoPoint) {
        Task { @MainActor in
            await model.search(center: center)
        }
    }

    private func refresh() {
        Task { @MainActor in
            await model.refresh()
        }
    }
}

private enum MapSheetRoute: String, Identifiable {
    case list
    case detail

    var id: String { rawValue }
}

@MainActor
private struct MapStatusCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let actionTitle: LocalizedStringKey?
    let action: (() -> Void)?
    let showsProgress: Bool

    init(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil,
        showsProgress: Bool = false
    ) {
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
        self.showsProgress = showsProgress
    }

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("state.loading"))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppColors.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.small)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.ink.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.status")
    }
}

private extension PhotoFilter {
    var titleKey: LocalizedStringKey {
        switch self {
        case .all:
            "map.filter.all"
        case .friends:
            "map.filter.friends"
        case .recent24Hours:
            "map.filter.recent"
        }
    }
}
