import SwiftUI

@main
struct MapGrapherApp: App {
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(isUITesting: isUITesting)
        }
    }
}
