import SwiftUI

@MainActor
struct RootTabs: View {
    let isUITesting: Bool
    private let photoReader: any PhotoReading
    private let locationProvider: any MapLocationProviding
    @StateObject private var router: AppRouter

    init(
        isUITesting: Bool = false,
        router: AppRouter? = nil,
        photoReader: any PhotoReading = FakePhotoReading(),
        locationProvider: any MapLocationProviding = FakeMapLocationProvider()
    ) {
        self.isUITesting = isUITesting
        self.photoReader = photoReader
        self.locationProvider = locationProvider
        _router = StateObject(wrappedValue: router ?? AppRouter())
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            MapScreen(
                isUITesting: isUITesting,
                photoReader: photoReader,
                locationProvider: locationProvider
            ) { route in
                router.navigate(to: route)
            }
            .tag(AppRoute.Tab.map)
            .tabItem {
                Label(AppStrings.map, systemImage: "map.fill")
                    .accessibilityLabel(Text(AppStrings.map))
            }

            GroupsPrototypeScreen()
                .tag(AppRoute.Tab.groups)
                .tabItem {
                    Label(AppStrings.groups, systemImage: "person.2.fill")
                        .accessibilityLabel(Text(AppStrings.groups))
                }

            NotificationsPrototypeScreen()
                .tag(AppRoute.Tab.notifications)
                .tabItem {
                    Label(AppStrings.notifications, systemImage: "bell.fill")
                        .accessibilityLabel(Text(AppStrings.notifications))
                }

            ProfilePrototypeScreen()
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
            PostComposerPlaceholderScreen()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fullScreenView(for route: AppRoute) -> some View {
        switch route {
        case .arPreview:
            ARProbeScreen(isUITesting: isUITesting)
        case .postComposer:
            PostComposerPlaceholderScreen()
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct PostComposerPlaceholderScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.large) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(AppColors.coral)
                    .accessibilityHidden(true)
                Text("route.post.title")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppColors.ink)
                Text("route.post.detail")
                    .font(.body)
                    .foregroundStyle(AppColors.ink.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("route.close") {
                    dismiss()
                }
                    .frame(minHeight: 44)
            }
            .padding(AppSpacing.xLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle("route.post.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("screen.post-composer")
        .accessibilityLabel(Text("route.post.title"))
    }
}
