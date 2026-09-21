import SwiftUI
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
        TabView(selection: $router.selectedTab) {
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
            .tabItem {
                Label(AppStrings.map, systemImage: "map.fill")
                    .accessibilityLabel(Text(AppStrings.map))
            }

            GroupListScreen(service: groupsService, context: sessionContext,
                            dataMode: groupsDataMode, postingService: postingService,
                            assetLoader: assetLoader,
                            isUITesting: isUITesting)
                .tag(AppRoute.Tab.groups)
                .tabItem {
                    Label(AppStrings.groups, systemImage: "person.2.fill")
                        .accessibilityLabel(Text(AppStrings.groups))
                }

            NotificationScreen(service: groupsService, context: sessionContext,
                               dataMode: groupsDataMode, postingService: postingService,
                               assetLoader: assetLoader,
                               isUITesting: isUITesting)
                .tag(AppRoute.Tab.notifications)
                .tabItem {
                    Label(AppStrings.notifications, systemImage: "bell.fill")
                        .accessibilityLabel(Text(AppStrings.notifications))
                }

            ProfileScreen(service: socialService, arRepository: arRepository,
                          sessionContext: sessionContext, assetLoader: assetLoader)
                .tag(AppRoute.Tab.profile)
                .tabItem {
                    Label(AppStrings.profile, systemImage: "person.crop.circle.fill")
                        .accessibilityLabel(Text(AppStrings.profile))
                }
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
            PostingFlowScreen(isUITesting: isUITesting, service: postingService)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fullScreenView(for route: AppRoute) -> some View {
        switch route {
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
            PostingFlowScreen(isUITesting: isUITesting, service: postingService)
        default:
            EmptyView()
        }
    }
}
