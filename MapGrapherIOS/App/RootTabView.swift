import SwiftUI

struct RootTabView: View {
    let isUITesting: Bool

    @State private var selectedTab: Tab = .map

    private enum Tab: Hashable {
        case map
        case groups
        case notifications
        case profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MapPrototypeScreen(isUITesting: isUITesting)
                .tag(Tab.map)
                .tabItem {
                    Label(AppStrings.map, systemImage: "map.fill")
                        .accessibilityLabel(Text(AppStrings.map))
                        .accessibilityIdentifier("tab.map")
                }

            GroupsPrototypeScreen()
                .tag(Tab.groups)
                .tabItem {
                    Label(AppStrings.groups, systemImage: "person.2.fill")
                        .accessibilityLabel(Text(AppStrings.groups))
                        .accessibilityIdentifier("tab.groups")
                }

            NotificationsPrototypeScreen()
                .tag(Tab.notifications)
                .tabItem {
                    Label(AppStrings.notifications, systemImage: "bell.fill")
                        .accessibilityLabel(Text(AppStrings.notifications))
                        .accessibilityIdentifier("tab.notifications")
                }

            ProfilePrototypeScreen()
                .tag(Tab.profile)
                .tabItem {
                    Label(AppStrings.profile, systemImage: "person.crop.circle.fill")
                        .accessibilityLabel(Text(AppStrings.profile))
                        .accessibilityIdentifier("tab.profile")
                }
        }
        .tint(AppColors.coral)
        .background(AppColors.paper)
    }
}
