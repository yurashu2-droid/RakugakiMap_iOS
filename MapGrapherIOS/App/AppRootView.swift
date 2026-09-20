import SwiftUI

@MainActor
struct AppRootView: View {
    @State private var container: AppContainer?
    @State private var configurationFailed = false
    @State private var pendingAuthURL: URL?

    var body: some View {
        Group {
            if let container {
                SessionRootView(container: container)
            } else if configurationFailed {
                ContentUnavailableView(
                    "接続設定がありません",
                    systemImage: "wifi.exclamationmark",
                    description: Text("検証用Supabaseの接続先と公開可能なキーを設定してから起動してください。")
                )
            } else {
                ProgressView("起動しています")
            }
        }
        .task {
            guard container == nil, !configurationFailed else { return }
            do {
                let created = AppContainer(gateway: try SupabaseGateway())
                container = created
                await created.start()
                if let pendingAuthURL {
                    try? await created.session.handleAuthURL(pendingAuthURL)
                    self.pendingAuthURL = nil
                }
            } catch {
                configurationFailed = true
            }
        }
        .onOpenURL { url in
            guard let container else {
                pendingAuthURL = url
                return
            }
            Task { try? await container.session.handleAuthURL(url) }
        }
    }
}

@MainActor
private struct SessionRootView: View {
    let container: AppContainer

    private var session: SessionController { container.session }

    var body: some View {
        switch session.state {
        case .restoring:
            ProgressView("ログイン状態を確認しています")
        case .authenticated:
            if let context = session.context {
                ProfileBootstrapView(container: container, context: context)
                    .id(context.epoch)
            } else {
                ProgressView("ログイン状態を確認しています")
            }
        case .signedOut, .awaitingEmailConfirmation, .reauthenticationRequired:
            WelcomeScreen(service: SessionAuthUIAdapter(session: session))
        }
    }
}
