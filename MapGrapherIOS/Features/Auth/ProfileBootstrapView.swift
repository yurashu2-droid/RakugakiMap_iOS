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
        // ログイン・新規登録の入力画面と同じ並び（題名、入力欄、主ボタン、文字だけのボタン）
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("プロフィールを決めよう")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.ink)
                    Text("地図やグループで、ほかの人に見える名前です。")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    TextField("表示名", text: $displayName)
                        .textContentType(.nickname)
                        .accessibilityIdentifier("profile.display-name")
                        .rakugakiField()
                    TextField("公開ID", text: $uniqueID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("profile.unique-id")
                        .rakugakiField()
                    Text("公開IDは英数字・_・.の3〜32文字です。")
                        .font(.footnote)
                        .foregroundStyle(AppColors.muted)
                }

                if case .failed(let message) = model.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.large)
                        .background(AppColors.shuTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                PrimaryButton(isLoading: model.state == .saving) {
                    Task { await model.submit(displayName: displayName, uniqueID: uniqueID) }
                } label: {
                    Text("始める")
                }
                .accessibilityIdentifier("profile.submit")

                HStack(spacing: AppSpacing.xLarge) {
                    if case .failed = model.state {
                        Button("接続を再確認") { Task { await model.load() } }
                            .frame(minHeight: 44)
                    }
                    Button("ログアウト") { Task { try? await container.session.signOut() } }
                        .frame(minHeight: 44)
                }
                .font(.footnote.weight(.bold))
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .tint(AppColors.link)
        .accessibilityIdentifier("screen.profile.setup")
    }
}
