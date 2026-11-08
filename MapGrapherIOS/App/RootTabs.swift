import Combine
import SwiftUI
import UIKit
import MapGrapherCore

@MainActor
struct RootTabs: View {
    let isUITesting: Bool
    private let photoReader: any PhotoReading
    private let photoRakugakiReader: any PhotoRakugakiReading
    private let locationProvider: any MapLocationProviding
    private let assetLoader: PrivateAssetLoader?
    private let sessionContext: SessionContext?
    private let postingService: any PostingUIService
    private let existingPhotoRakugakiService: (any ExistingPhotoRakugakiServing)?
    private let socialService: any SocialProfileUIService
    private let photoService: any PhotoDetailUIService
    private let groupsService: any GroupsServing
    private let groupsDataMode: GroupUIDataMode
    private let arRepository: (any ARExperienceServing)?
    private let arSession: (any SessionProviding)?
    @StateObject private var router: AppRouter
    @State private var isKeyboardVisible = false

    init(
        isUITesting: Bool = false,
        router: AppRouter? = nil,
        photoReader: any PhotoReading = FakePhotoReading(),
        photoRakugakiReader: any PhotoRakugakiReading = FakePhotoRakugakiReader(),
        locationProvider: any MapLocationProviding = FakeMapLocationProvider(),
        assetLoader: PrivateAssetLoader? = nil,
        sessionContext: SessionContext? = nil,
        postingService: any PostingUIService = FakePostingUIService(),
        existingPhotoRakugakiService: (any ExistingPhotoRakugakiServing)? = nil,
        socialService: any SocialProfileUIService = FakeSocialProfileUIService(),
        photoService: any PhotoDetailUIService = FakePhotoDetailUIService(),
        groupsService: any GroupsServing = FakeGroupsServing(),
        groupsDataMode: GroupUIDataMode = .fake,
        arRepository: (any ARExperienceServing)? = nil,
        arSession: (any SessionProviding)? = nil
    ) {
        self.isUITesting = isUITesting
        self.photoReader = photoReader
        self.photoRakugakiReader = photoRakugakiReader
        self.locationProvider = locationProvider
        self.assetLoader = assetLoader
        self.sessionContext = sessionContext
        self.postingService = postingService
        self.existingPhotoRakugakiService = existingPhotoRakugakiService
        self.socialService = socialService
        self.photoService = photoService
        self.groupsService = groupsService
        self.groupsDataMode = groupsDataMode
        self.arRepository = arRepository
        self.arSession = arSession
        _router = StateObject(wrappedValue: router ?? AppRouter())
    }

    var body: some View {
        // 標準のタブバーは隠し、案Aの浮かせたタブ（選んだタブにインクのしぶき）を下に置く。
        // 地図の下のツールバーなどが隠れないよう、タブは画面の上に重ねず、画面の下に並べる
        VStack(spacing: 0) {
            TabView(selection: $router.selectedTab) {
                TodayScreen(
                    groupsService: groupsService,
                    context: sessionContext,
                    groupsDataMode: groupsDataMode,
                    socialService: socialService,
                    onOpenTab: { tab in router.navigate(to: .tab(tab)) },
                    onPresentRoute: { route in router.navigate(to: route) }
                )
                .tag(AppRoute.Tab.today)
                .toolbar(.hidden, for: .tabBar)

                GroupListScreen(service: groupsService, context: sessionContext,
                                dataMode: groupsDataMode, postingService: postingService,
                                assetLoader: assetLoader,
                                isUITesting: isUITesting)
                    .tag(AppRoute.Tab.groups)
                    .toolbar(.hidden, for: .tabBar)

                MapScreen(
                    isUITesting: isUITesting,
                    photoReader: photoReader,
                    photoRakugakiReader: photoRakugakiReader,
                    locationProvider: locationProvider,
                    assetLoader: assetLoader,
                    sessionContext: sessionContext,
                    existingPhotoRakugakiService: existingPhotoRakugakiService,
                    photoService: photoService
                ) { route in
                    router.navigate(to: route)
                }
                .tag(AppRoute.Tab.map)
                .toolbar(.hidden, for: .tabBar)

                NotificationScreen(service: groupsService, context: sessionContext,
                                   dataMode: groupsDataMode, postingService: postingService,
                                   assetLoader: assetLoader,
                                   isUITesting: isUITesting)
                    .tag(AppRoute.Tab.notifications)
                    .toolbar(.hidden, for: .tabBar)

                ProfileScreen(service: socialService, arRepository: arRepository,
                              sessionContext: sessionContext, assetLoader: assetLoader)
                    .tag(AppRoute.Tab.profile)
                    .toolbar(.hidden, for: .tabBar)
            }
            // 文字を打つ間はタブをしまい、入力欄にキーボードの上を使わせる
            if !isKeyboardVisible {
                RakugakiTabBar(selection: $router.selectedTab)
            }
        }
        .background(AppColors.paper.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .tint(AppColors.coral)
        .background(AppColors.paper)
        .sheet(item: $router.sheetRoute) { route in
            sheetView(for: route)
        }
        .fullScreenCover(item: $router.fullScreenRoute) { route in
            fullScreenView(for: route)
        }
    }

    @ViewBuilder
    private func sheetView(for route: AppRoute) -> some View {
        switch route {
        case .postComposer:
            PostingFlowScreen(
                isUITesting: isUITesting,
                service: postingService,
                arRepository: arRepository,
                imageLoader: assetLoader,
                sessionContext: sessionContext
            )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fullScreenView(for route: AppRoute) -> some View {
        switch route {
        case .spatialARDrawing:
            SpatialARDrawingScreen(isUITesting: isUITesting)
        case .arPreview, .arPhoto:
            if let arRepository, let assetLoader, let sessionContext, let arSession {
                ARExplorerFlow(repository: arRepository, assetLoader: assetLoader,
                               session: arSession, context: sessionContext,
                               targetPhotoID: {
                                   if case .arPhoto(let id) = route { return id }
                                   return nil
                               }())
            } else {
                ARProbeScreen(isUITesting: isUITesting)
            }
        case .postComposer:
            PostingFlowScreen(
                isUITesting: isUITesting,
                service: postingService,
                arRepository: arRepository,
                imageLoader: assetLoader,
                sessionContext: sessionContext
            )
        default:
            EmptyView()
        }
    }
}
