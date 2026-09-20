import SwiftUI
import MapGrapherCore

@MainActor
struct ProfileBootstrapView: View {
    let container: AppContainer
    let context: SessionContext

    @State private var model: ProfileBootstrapModel
    @State private var displayName = ""
    @State private var uniqueID = ""

    init(container: AppContainer, context: SessionContext) {
        self.container = container
        self.context = context
        _model = State(initialValue: ProfileBootstrapModel(context: context, session: container.session,
            service: SupabaseProfileBootstrapService(gateway: container.gateway,
                                                     session: container.session)))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("プロフィールを確認しています")
            case .ready:
                RootTabs(photoReader: container.photoReader,
                         photoRakugakiReader: container.photoRakugakiReader,
                         locationProvider: container.mapLocationProvider,
                         assetLoader: container.assetLoader,
                         sessionContext: context,
                         postingService: container.postingService(for: context),
                         existingPhotoRakugakiService: container.existingPhotoRakugakiService(for: context),
                         socialService: container.socialService(for: context),
                         photoService: container.photoDetailService(for: context),
                         groupsService: container.groupsService,
                         groupsDataMode: .live,
                         arRepository: container.arRepository,
                         arSession: container.session)
            case .needsProfile, .saving, .failed:
                setupForm
            }
        }
        .task { await model.load() }
    }

    private var setupForm: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("表示名", text: $displayName)
                        .textContentType(.nickname)
                        .accessibilityIdentifier("profile.display-name")
                    TextField("公開ID", text: $uniqueID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("profile.unique-id")
                } footer: {
                    Text("公開IDは英数字・_・.の3〜32文字です。")
                }
                if case .failed(let message) = model.state {
                    Section { Text(message).foregroundStyle(.red) }
                }
                Section {
                    Button("始める") {
                        Task { await model.submit(displayName: displayName, uniqueID: uniqueID) }
                    }
                    .disabled(model.state == .saving)
                    .accessibilityIdentifier("profile.submit")
                    if case .failed = model.state {
                        Button("接続を再確認") { Task { await model.load() } }
                    }
                    Button("ログアウト") { Task { try? await container.session.signOut() } }
                }
            }
            .navigationTitle("プロフィール設定")
            .accessibilityIdentifier("screen.profile.setup")
        }
    }
}
