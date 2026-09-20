import Combine
import Foundation

enum AppRoute: Hashable, Identifiable {
    enum Tab: String, CaseIterable, Hashable, Sendable {
        case map
        case groups
        case notifications
        case profile

        var id: String { rawValue }
    }

    case welcome
    case signIn
    case signUp
    case passwordReset
    case tab(Tab)
    case postComposer
    case arPreview

    var id: String {
        switch self {
        case .welcome:
            "welcome"
        case .signIn:
            "sign-in"
        case .signUp:
            "sign-up"
        case .passwordReset:
            "password-reset"
        case .tab(let tab):
            "tab.\(tab.rawValue)"
        case .postComposer:
            "post-composer"
        case .arPreview:
            "ar-preview"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppRoute.Tab = .map
    @Published var sheetRoute: AppRoute?
    @Published var fullScreenRoute: AppRoute?
    @Published private(set) var path: [AppRoute] = []

    func navigate(to route: AppRoute) {
        switch route {
        case .tab(let tab):
            selectedTab = tab
            path.removeAll()
        case .postComposer, .arPreview:
            fullScreenRoute = route
        case .welcome, .signIn, .signUp, .passwordReset:
            path.append(route)
        }
    }

    func dismissFullScreen() {
        fullScreenRoute = nil
    }

    func presentSheet(_ route: AppRoute) {
        sheetRoute = route
    }

    func dismissSheet() {
        sheetRoute = nil
    }

    func resetAfterLogout() {
        path.removeAll()
        sheetRoute = nil
        fullScreenRoute = nil
        selectedTab = .map
    }
}
