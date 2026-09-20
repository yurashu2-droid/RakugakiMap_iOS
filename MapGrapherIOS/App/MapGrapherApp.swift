import SwiftUI

@main
struct MapGrapherApp: App {
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    var body: some Scene {
        WindowGroup {
            if isUITesting {
                if ProcessInfo.processInfo.arguments.contains("--auth-ui-testing") {
                    WelcomeScreen(service: FakeAuthUIService())
                } else {
                    RootTabs(isUITesting: true)
                }
            } else {
                AppRootView()
            }
        }
    }
}
